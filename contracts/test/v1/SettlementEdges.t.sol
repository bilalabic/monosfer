// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

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
 * @notice Settlement under configurations the main suite never reaches.
 * @dev The unit suite fixes `BID_DEPOSIT = 1 ether` against `COLLATERAL = 5
 *      ether` and a 2% fee on a 10 MON ask, which keeps every quantity
 *      comfortably non-zero and the bid deposit comfortably below the coverage.
 *      Both of the defects pinned here live outside that window, which is why
 *      they survived a green suite.
 */
contract SettlementEdgesTest is QuoteFixture, PickupFixture, PodFixture {
    ProtocolAccessManager internal manager;
    ProtocolConfig internal config;
    SettlementVault internal vault;
    CourierRegistry internal registry;
    ReputationRegistry internal reputation;
    Referral internal referral;
    DeliveryHub internal hub;

    address internal admin = address(0xA11CE);
    address internal configAdmin = address(0xC0F1);
    address internal treasury = address(0x7EA5);

    address internal customer;
    uint256 internal constant COURIER_KEY = 0xC0DE10;
    address internal courier;

    uint96 internal constant BID_DEPOSIT = 1 ether;

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
        manager.grantRole(manager.CONFIG_ADMIN_ROLE(), configAdmin);
        vm.stopPrank();

        uint256 deposit = config.courierBaseDeposit();
        vm.deal(customer, 1_000 ether);
        vm.deal(courier, 1_000 ether);
        uint256 stakeAmount = deposit + 20 ether;
        vm.prank(courier);
        registry.depositStake{value: stakeAmount}();
    }

    // ------------------------------------------------------------ helpers

    /// @dev Drives one delivery all the way to `Completed` with the given terms.
    function _runDelivery(uint96 declaredValue, uint96 ask, uint96 returnAsk) internal returns (uint256 id) {
        CoverageQuote.Quote memory q = buildQuote(config, customer, 1, declaredValue);
        bytes memory qsig = signQuote(hub, q);
        vm.prank(customer);
        id = hub.createDelivery(q, qsig);

        vm.prank(courier);
        hub.placeBid(id, ask, returnAsk, 30, uint64(block.timestamp + 1 hours));

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

        DeliveryProof.Attestation memory att = buildAttestation(config, id, courier);
        bytes memory psig = signAttestation(hub, att);
        vm.prank(courier);
        hub.submitDeliveryProof(id, att, psig);

        vm.prank(customer);
        hub.confirmDelivery(id);
    }

    // ------------------------------------------------- a zero protocol fee

    /**
     * @dev A fee of zero is inside the configured bounds — `protocolFeeBps` has a
     *      ceiling and no floor — and settlement has to cope with it. It used to
     *      emit a zero-amount payout leg, which the vault refuses, so the
     *      delivery could never leave `DeliveredPending`: no deadline left to
     *      trip, escrow and coverage locked, and one of the customer's listing
     *      slots consumed for good.
     */
    function test_ZeroProtocolFeeStillSettles() public {
        ProtocolConfig.Params memory p = config.params();
        p.protocolFeeBps = 0;
        vm.prank(configAdmin);
        config.proposeParams(p);
        vm.warp(block.timestamp + 2 days);
        vm.prank(configAdmin);
        config.executeParams();
        assertEq(config.protocolFeeBps(), 0, "a zero fee is a legal configuration");

        uint256 id = _runDelivery(20 ether, 10 ether, 2 ether);

        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.Completed));
        assertEq(vault.claimableOf(courier), 10 ether, "courier paid in full");
        assertEq(vault.claimableOf(customer), 2 ether, "unused return reserve returned");
        assertEq(vault.claimableOf(treasury), 0, "and the treasury is owed nothing");
    }

    /// @dev The same hole, reached without touching config: 2% of 49 wei is zero.
    function test_AskTooSmallToRoundAFeeStillSettles() public {
        uint256 id = _runDelivery(20 ether, 49, 0);

        assertEq(hub.deliveryOf(id).protocolFee, 0, "the fee rounded away");
        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.Completed));
        assertEq(vault.claimableOf(courier), 49);
    }

    /// @dev A return reserve of zero is the third way to produce an empty leg.
    function test_ZeroReturnReserveStillSettles() public {
        uint256 id = _runDelivery(20 ether, 10 ether, 0);

        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.Completed));
        assertEq(vault.claimableOf(courier), 10 ether);
        assertEq(vault.claimableOf(customer), 0);
    }

    // --------------------------------------- coverage below the bid deposit

    /**
     * @dev `placeBid` reserves `bidDeposit`, and `fundAsCourier` tops that up to
     *      the coverage rather than releasing and re-taking it, so the standing
     *      reservation is the larger of the two. When the coverage is smaller —
     *      which it is for any parcel under about 5.3 MON at the default deposit
     *      — releasing only the coverage left the difference locked with no code
     *      path anywhere to free it, and a courier carrying a reservation can
     *      never deregister.
     */
    function test_SmallParcelLeavesNoCollateralBehind() public {
        // 25% of 2 MON is 0.5 MON, well under the 1 MON bid deposit.
        uint256 id = _runDelivery(2 ether, 1 ether, 0.2 ether);

        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.Completed));
        assertEq(registry.courierOf(courier).reserved, 0, "nothing stayed locked");

        // The real consequence: an exit that would otherwise be refused forever.
        vm.prank(courier);
        registry.deregister();
    }

    function test_CancelledSmallParcelAlsoReleasesEverything() public {
        CoverageQuote.Quote memory q = buildQuote(config, customer, 1, 2 ether);
        bytes memory qsig = signQuote(hub, q);
        vm.prank(customer);
        uint256 id = hub.createDelivery(q, qsig);

        vm.prank(courier);
        hub.placeBid(id, 1 ether, 0.2 ether, 30, uint64(block.timestamp + 1 hours));
        uint32 version = hub.bidOf(id, courier).termsVersion;
        vm.prank(customer);
        hub.selectCourier(id, courier, version);

        uint256 amount = hub.customerFundingAmount(id);
        vm.prank(customer);
        hub.fundAsCustomer{value: amount}(id);
        vm.prank(courier);
        hub.fundAsCourier(id);

        // Nobody picks it up; the window closes.
        vm.warp(block.timestamp + config.pickupWindow() + 1);
        hub.poke(id);

        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.Cancelled));
        assertEq(registry.courierOf(courier).reserved, 0, "a cancelled delivery frees it too");
    }

    /// @dev Whatever the parcel is worth, the courier ends up owing nothing.
    function testFuzz_ReservationAlwaysReturnsToZero(uint96 declaredValue, uint96 ask) public {
        declaredValue = uint96(bound(declaredValue, 1 ether, 40 ether));
        ask = uint96(bound(ask, 1, 5 ether));

        _runDelivery(declaredValue, ask, 0);
        assertEq(registry.courierOf(courier).reserved, 0, "no reservation survives a completed delivery");
    }
}
