// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {ProtocolAccessManager} from "../../src/v1/access/ProtocolAccessManager.sol";
import {ProtocolConfig} from "../../src/v1/config/ProtocolConfig.sol";
import {BaselineParams} from "../../src/v1/config/BaselineParams.sol";
import {SettlementVault} from "../../src/v1/vault/SettlementVault.sol";
import {CourierRegistry} from "../../src/v1/registry/CourierRegistry.sol";
import {DeliveryHub} from "../../src/v1/hub/DeliveryHub.sol";
import {ReputationRegistry} from "../../src/v1/reputation/ReputationRegistry.sol";
import {Referral} from "../../src/v1/rewards/Referral.sol";
import {CoverageQuote} from "../../src/v1/risk/CoverageQuote.sol";
import {PickupProof} from "../../src/v1/proof/PickupProof.sol";
import {DeliveryProof} from "../../src/v1/proof/DeliveryProof.sol";
import {QuoteFixture} from "./helpers/QuoteFixture.sol";
import {PickupFixture} from "./helpers/PickupFixture.sol";
import {PodFixture} from "./helpers/PodFixture.sol";

/**
 * @notice The delivery lifecycle feeding reputation (sec. 19, sec. 13, sec. 20).
 * @dev The registry's arithmetic is covered in `ReputationRegistry.t.sol`. What
 *      is proven here is the wiring: that outcomes actually arrive, that
 *      punctuality is judged against the ETA the courier accepted, and — the one
 *      that matters most — that a broken reputation subsystem cannot hold up
 *      anyone's money.
 */
contract ReputationWiringTest is QuoteFixture, PickupFixture, PodFixture {
    ProtocolAccessManager internal manager;
    ProtocolConfig internal config;
    SettlementVault internal vault;
    CourierRegistry internal registry;
    ReputationRegistry internal reputation;
    Referral internal referral;
    DeliveryHub internal hub;

    address internal admin = address(0xA11CE);
    address internal treasury = address(0x7EA5);
    address internal treasurer = address(0x7EA57);
    address internal customerReferrer = address(0xDEF1);
    address internal courierReferrer = address(0xDEF2);

    uint128 internal constant REFERRAL_REWARD = 0.5 ether;

    address internal customer;
    uint256 internal constant COURIER_KEY = 0xC0DE10;
    address internal courier;

    uint96 internal constant BID_DEPOSIT = 1 ether;
    uint96 internal constant DECLARED_VALUE = 20 ether;
    uint96 internal constant ASK = 10 ether;
    uint96 internal constant RETURN_ASK = 2 ether;
    uint32 internal constant ETA_MINUTES = 30;

    function setUp() public {
        customer = senderAddress(0);
        courier = vm.addr(COURIER_KEY);

        manager = new ProtocolAccessManager(3 days, admin);
        config = new ProtocolConfig(
            manager, 2 days, BaselineParams.baseline(), treasury, quoteSignerAddress(), podSignerAddress()
        );
        vault = new SettlementVault(manager);
        registry = new CourierRegistry(manager, config, vault);
        reputation = new ReputationRegistry(manager);
        referral = new Referral(manager);
        hub = new DeliveryHub(manager, config, registry, vault, reputation, referral, BID_DEPOSIT);

        vm.startPrank(admin);
        manager.grantRole(manager.VAULT_CONTROLLER_ROLE(), address(registry));
        manager.grantRole(manager.VAULT_CONTROLLER_ROLE(), address(hub));
        manager.grantRole(manager.REGISTRY_CONTROLLER_ROLE(), address(hub));
        manager.grantRole(manager.REPUTATION_REPORTER_ROLE(), address(hub));
        manager.grantRole(manager.REFERRAL_REPORTER_ROLE(), address(hub));
        manager.grantRole(manager.TREASURER_ROLE(), treasurer);
        vm.stopPrank();

        vm.prank(treasurer);
        referral.setRewardAmount(REFERRAL_REWARD);
        vm.deal(treasurer, 100 ether);
        vm.prank(treasurer);
        referral.fund{value: 10 ether}();

        vm.deal(customer, 1_000 ether);
        vm.deal(courier, 1_000 ether);
        // Amount read before the cheatcode: a view call inside the {value:}
        // expression is evaluated after `vm.prank` and consumes it, which would
        // stake the test contract instead of the courier.
        uint256 stakeAmount = config.courierBaseDeposit() + 20 ether;
        vm.prank(courier);
        registry.depositStake{value: stakeAmount}();
    }

    // ------------------------------------------------------------ helpers

    function _toInTransit() internal returns (uint256 id) {
        CoverageQuote.Quote memory q = buildQuote(config, customer, 1, DECLARED_VALUE);
        bytes memory qsig = signQuote(hub, q);
        vm.prank(customer);
        id = hub.createDelivery(q, qsig);

        vm.prank(courier);
        hub.placeBid(id, ASK, RETURN_ASK, ETA_MINUTES, uint64(block.timestamp + 1 hours));

        uint32 version = hub.bidOf(id, courier).termsVersion;
        vm.prank(customer);
        hub.selectCourier(id, courier, version);

        uint256 amount = hub.customerFundingAmount(id);
        vm.prank(customer);
        hub.fundAsCustomer{value: amount}(id);
        vm.prank(courier);
        hub.fundAsCourier(id);

        PickupProof.Acceptance memory acc = buildAcceptance(id, courier);
        bytes memory asig = signAcceptance(hub, acc, senderKey(0));
        vm.prank(courier);
        hub.confirmPickup(id, acc, asig);
    }

    function _deliver(uint256 id) internal {
        DeliveryProof.Attestation memory a = buildAttestation(config, id, courier);
        bytes memory sig = signAttestation(hub, a);
        vm.prank(courier);
        hub.submitDeliveryProof(id, a, sig);
    }

    function _complete(uint256 id) internal {
        _deliver(id);
        vm.prank(customer);
        hub.confirmDelivery(id);
    }

    // --------------------------------------------------------- the wiring

    function test_SelectionIsRecordedAsAnAssignment() public {
        _toInTransit();
        assertEq(reputation.recordOf(courier).assignments, 1, "selection must reach the registry");
    }

    function test_CompletedDeliveryIsRecorded() public {
        uint256 id = _toInTransit();
        _complete(id);

        ReputationRegistry.Record memory r = reputation.recordOf(courier);
        assertEq(r.completed, 1);
        assertEq(r.onTime, 1, "delivered well inside the accepted ETA");
        assertGt(reputation.confidenceOf(courier), 0, "one delivery is some history");
    }

    /// @dev sec. 13: punctuality is measured against the courier's own accepted ETA.
    function test_LatenessIsJudgedAgainstTheAcceptedEta() public {
        uint256 id = _toInTransit();

        // Past the ETA the courier itself bid, but still inside the transit window.
        vm.warp(block.timestamp + uint256(ETA_MINUTES) * 1 minutes + 1);
        _complete(id);

        ReputationRegistry.Record memory r = reputation.recordOf(courier);
        assertEq(r.completed, 1);
        assertEq(r.onTime, 0, "past the accepted ETA is late, whatever the protocol window says");
    }

    /// @dev A different bid means a different deadline, from the same contract.
    function test_ALongerBidEtaBuysMoreTime() public {
        CoverageQuote.Quote memory q = buildQuote(config, customer, 1, DECLARED_VALUE);
        bytes memory qsig = signQuote(hub, q);
        vm.prank(customer);
        uint256 id = hub.createDelivery(q, qsig);

        vm.prank(courier);
        hub.placeBid(id, ASK, RETURN_ASK, 600, uint64(block.timestamp + 1 hours));
        uint32 version = hub.bidOf(id, courier).termsVersion;
        vm.prank(customer);
        hub.selectCourier(id, courier, version);

        uint256 amount = hub.customerFundingAmount(id);
        vm.prank(customer);
        hub.fundAsCustomer{value: amount}(id);
        vm.prank(courier);
        hub.fundAsCourier(id);

        PickupProof.Acceptance memory acc = buildAcceptance(id, courier);
        bytes memory asig = signAcceptance(hub, acc, senderKey(0));
        vm.prank(courier);
        hub.confirmPickup(id, acc, asig);

        // Same elapsed time that was late on a 30-minute ETA.
        vm.warp(block.timestamp + uint256(ETA_MINUTES) * 1 minutes + 1);
        _complete(id);

        assertEq(reputation.recordOf(courier).onTime, 1, "a 600-minute ETA is not missed in 31 minutes");
    }

    /// @dev A cancelled delivery is not attributed to the courier without evidence.
    function test_CancellationIsNotBlamedOnTheCourier() public {
        CoverageQuote.Quote memory q = buildQuote(config, customer, 1, DECLARED_VALUE);
        bytes memory qsig = signQuote(hub, q);
        vm.prank(customer);
        uint256 id = hub.createDelivery(q, qsig);

        vm.prank(courier);
        hub.placeBid(id, ASK, RETURN_ASK, ETA_MINUTES, uint64(block.timestamp + 1 hours));
        uint32 version = hub.bidOf(id, courier).termsVersion;
        vm.prank(customer);
        hub.selectCourier(id, courier, version);

        // Nobody funds; the window closes.
        vm.warp(block.timestamp + config.fundingWindow() + 1);
        hub.poke(id);

        ReputationRegistry.Record memory r = reputation.recordOf(courier);
        assertEq(r.assignments, 1, "the assignment still counts");
        assertEq(r.cancelledByCourier, 0, "but the failure is not pinned on them");
        assertEq(r.courierFailed, 0);
    }

    // ------------------------------------------------------ sec. 20 rating

    function test_CustomerCanRateAfterCompletion() public {
        uint256 id = _toInTransit();
        _complete(id);

        vm.prank(customer);
        hub.rateCourier(id, 5);

        assertEq(reputation.recordOf(courier).ratingCount, 1);
        assertEq(reputation.averageRatingBps(courier), 5 * 10_000);
    }

    function test_OnlyTheCustomerMayRate() public {
        uint256 id = _toInTransit();
        _complete(id);

        vm.prank(courier);
        vm.expectRevert(abi.encodeWithSelector(DeliveryHub.NotCustomer.selector, courier));
        hub.rateCourier(id, 5);
    }

    function test_RatingBeforeCompletionIsRejected() public {
        uint256 id = _toInTransit();
        vm.prank(customer);
        vm.expectRevert();
        hub.rateCourier(id, 5);
    }

    function test_RatingAfterTheWindowIsRejected() public {
        uint256 id = _toInTransit();
        _complete(id);

        vm.warp(block.timestamp + config.ratingWindow() + 1);
        vm.prank(customer);
        vm.expectRevert();
        hub.rateCourier(id, 5);
    }

    function test_RatingOnTheFinalDayIsAccepted() public {
        uint256 id = _toInTransit();
        _complete(id);

        vm.warp(block.timestamp + config.ratingWindow());
        vm.prank(customer);
        hub.rateCourier(id, 4);
        assertEq(reputation.recordOf(courier).ratingCount, 1);
    }

    function test_SecondRatingOnTheSameDeliveryIsRejected() public {
        uint256 id = _toInTransit();
        _complete(id);

        vm.prank(customer);
        hub.rateCourier(id, 5);
        vm.prank(customer);
        vm.expectRevert(abi.encodeWithSelector(ReputationRegistry.DeliveryAlreadyRated.selector, id));
        hub.rateCourier(id, 1);
    }

    // ------------------------------------------ the property that matters

    /**
     * @dev Reputation must never be able to hold up money. The registry is
     *      stripped of its writer role mid-flight, which makes every report
     *      revert; settlement has to carry on and pay out in full regardless.
     *
     *      This is the failure the plan calls out for badges — a cosmetic
     *      subsystem bricking settlement — and the same discipline applies here,
     *      because reputation is just as far from custody of funds.
     */
    function test_BrokenReputationCannotBlockSettlement() public {
        uint256 id = _toInTransit();

        bytes32 role = manager.REPUTATION_REPORTER_ROLE();
        vm.prank(admin);
        manager.revokeRole(role, address(hub));

        _complete(id);

        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.Completed), "settled anyway");
        assertEq(vault.claimableOf(courier), ASK, "courier paid in full");
        assertEq(vault.claimableOf(customer), RETURN_ASK, "unused return reserve returned");
        assertEq(reputation.recordOf(courier).completed, 0, "and the write was indeed refused");
    }

    /// @dev The failure is surfaced as an event rather than swallowed silently.
    function test_FailedReportIsObservable() public {
        bytes32 role = manager.REPUTATION_REPORTER_ROLE();
        vm.prank(admin);
        manager.revokeRole(role, address(hub));

        CoverageQuote.Quote memory q = buildQuote(config, customer, 1, DECLARED_VALUE);
        bytes memory qsig = signQuote(hub, q);
        vm.prank(customer);
        uint256 id = hub.createDelivery(q, qsig);
        vm.prank(courier);
        hub.placeBid(id, ASK, RETURN_ASK, ETA_MINUTES, uint64(block.timestamp + 1 hours));
        uint32 version = hub.bidOf(id, courier).termsVersion;

        vm.expectEmit(false, false, false, false, address(hub));
        emit DeliveryHub.ReputationReportFailed("");
        vm.prank(customer);
        hub.selectCourier(id, courier, version);

        assertEq(reputation.recordOf(courier).assignments, 0, "and the write did not land");
    }

    // ------------------------------------------------ sec. 25: qualification

    /**
     * @dev sec. 25 pays a referrer when the wallet they brought in *does*
     *      something, and a completed delivery is the canonical act for both
     *      sides of it. The registry had this function and no caller for a
     *      while, which is a subtler kind of missing feature than a missing
     *      function: everything compiles, every test passes, and no referrer is
     *      ever paid.
     */
    function test_ACompletedDeliveryQualifiesBothSides() public {
        vm.prank(customer);
        referral.register(customerReferrer);
        vm.prank(courier);
        referral.register(courierReferrer);

        uint256 id = _toInTransit();
        _complete(id);

        assertTrue(referral.qualified(customer), "the customer ordered");
        assertTrue(referral.qualified(courier), "the courier carried");
        assertEq(referral.claimable(customerReferrer), REFERRAL_REWARD, "and each referrer is owed once");
        assertEq(referral.claimable(courierReferrer), REFERRAL_REWARD);
    }

    /// @dev One reward per wallet, not one per delivery (sec. 25).
    function test_ASecondDeliveryPaysTheReferrerNothingMore() public {
        vm.prank(customer);
        referral.register(customerReferrer);

        _complete(_toInTransit());
        assertEq(referral.claimable(customerReferrer), REFERRAL_REWARD);

        uint256 second = _toInTransit();
        _complete(second);

        assertEq(uint8(hub.deliveryOf(second).state), uint8(DeliveryHub.State.Completed), "and it still settles");
        assertEq(referral.claimable(customerReferrer), REFERRAL_REWARD, "paid once, not twice");
    }

    /**
     * @dev sec. 25 states it outright: a referral failure must never block
     *      settlement. Revoking the hub's reporter role is the operational shape
     *      of that failure -- every qualification call now reverts -- and money
     *      must keep moving regardless.
     */
    function test_ABrokenReferralCannotBlockSettlement() public {
        vm.prank(customer);
        referral.register(customerReferrer);

        bytes32 role = manager.REFERRAL_REPORTER_ROLE();
        vm.prank(admin);
        manager.revokeRole(role, address(hub));

        uint256 id = _toInTransit();
        _complete(id);

        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.Completed), "settled anyway");
        assertEq(vault.claimableOf(courier), ASK, "and the courier was paid");
        assertFalse(referral.qualified(customer), "the qualification is simply lost");
        assertEq(referral.claimable(customerReferrer), 0);
    }

    /// @dev And the loss is visible rather than silent.
    function test_AFailedQualificationIsObservable() public {
        bytes32 role = manager.REFERRAL_REPORTER_ROLE();
        vm.prank(admin);
        manager.revokeRole(role, address(hub));

        uint256 id = _toInTransit();
        _deliver(id);

        vm.recordLogs();
        vm.prank(customer);
        hub.confirmDelivery(id);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256("ReferralReportFailed(address,bytes)");
        uint256 failures;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == topic) failures++;
        }
        assertEq(failures, 2, "one for the customer, one for the courier");
    }
}
