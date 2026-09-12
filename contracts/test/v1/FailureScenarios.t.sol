// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ProtocolAccessManager} from "../../src/v1/access/ProtocolAccessManager.sol";
import {ProtocolConfig} from "../../src/v1/config/ProtocolConfig.sol";
import {BaselineParams} from "../../src/v1/config/BaselineParams.sol";
import {SettlementVault} from "../../src/v1/vault/SettlementVault.sol";
import {CourierRegistry} from "../../src/v1/registry/CourierRegistry.sol";
import {ReputationRegistry} from "../../src/v1/reputation/ReputationRegistry.sol";
import {Referral} from "../../src/v1/rewards/Referral.sol";
import {DeliveryHub} from "../../src/v1/hub/DeliveryHub.sol";
import {JurorPool} from "../../src/v1/dispute/JurorPool.sol";
import {DisputeCourt} from "../../src/v1/dispute/DisputeCourt.sol";
import {FallbackCommittee} from "../../src/v1/dispute/FallbackCommittee.sol";
import {IRandomnessAdapter} from "../../src/v1/randomness/IRandomnessAdapter.sol";
import {CoverageQuote} from "../../src/v1/risk/CoverageQuote.sol";
import {PickupProof} from "../../src/v1/proof/PickupProof.sol";
import {DeliveryProof} from "../../src/v1/proof/DeliveryProof.sol";
import {QuoteFixture} from "./helpers/QuoteFixture.sol";
import {PickupFixture} from "./helpers/PickupFixture.sol";
import {PodFixture} from "./helpers/PodFixture.sol";

/// @dev A randomness adapter that answers nothing, so the draw path is reachable
///      without being the subject of this suite.
contract SilentRandomness is IRandomnessAdapter {
    uint64 public nextId = 1;

    function fee() external pure returns (uint256) {
        return 0;
    }

    function request(bytes32) external payable returns (uint64) {
        return nextId++;
    }

    function randomnessOf(uint64) external pure returns (bytes32, bool) {
        return (bytes32(0), false);
    }

    function isFulfilled(uint64) external pure returns (bool) {
        return false;
    }

    function requesterOf(uint64) external pure returns (address) {
        return address(0);
    }
}

/// @notice A customer wallet that cannot receive MON.
/// @dev Not contrived: a Gnosis Safe with no fallback, a contract with a
///      `receive` that runs out of gas, or a wallet that simply reverts on value
///      are all real. sec. 18.2 exists because of them.
contract RejectingWallet {
    receive() external payable {
        revert("no MON here");
    }

    function call(address target, bytes memory data) external payable returns (bytes memory) {
        (bool ok, bytes memory out) = target.call{value: msg.value}(data);
        if (!ok) {
            assembly {
                revert(add(out, 32), mload(out))
            }
        }
        return out;
    }
}

/**
 * @notice The baseline's required failure tests (sec. 47) and the invariants
 *         (sec. 33) that had no named test of their own.
 * @dev The rest of sec. 33 and sec. 47 is pinned in the suite that owns the
 *      behaviour — `docs/testing.md` maps every line to its test. What lives
 *      here is what nothing else claimed, which is why the file reads as a list
 *      of unrelated failures rather than as one contract's tests.
 *
 *      Three sec. 47 entries are **deliberately absent**: indexer outage and
 *      replay, RPC provider failure, and a backend retry producing a duplicate
 *      request. None of them is a contract behaviour — they are properties of
 *      the services that read and write the chain, and a Solidity test asserting
 *      anything about them would be theatre. They are listed in `testing.md`
 *      against the backend instead.
 */
contract FailureScenariosTest is QuoteFixture, PickupFixture, PodFixture {
    ProtocolAccessManager internal manager;
    ProtocolConfig internal config;
    SettlementVault internal vault;
    CourierRegistry internal registry;
    ReputationRegistry internal reputation;
    Referral internal referral;
    DeliveryHub internal hub;
    JurorPool internal pool;
    DisputeCourt internal court;
    FallbackCommittee internal committee;
    SilentRandomness internal rng;

    address internal admin = address(0xA11CE);
    address internal treasury = address(0x7EA5);
    address internal customer;
    address internal courier = address(0xC0DE);

    uint96 internal constant BID_DEPOSIT = 1 ether;
    uint96 internal constant DECLARED_VALUE = 20 ether;
    uint96 internal constant ASK = 10 ether;
    uint96 internal constant RETURN_ASK = 2 ether;

    function setUp() public {
        customer = senderAddress(0);

        manager = new ProtocolAccessManager(3 days, admin);
        config = new ProtocolConfig(
            manager, 2 days, BaselineParams.baseline(), treasury, quoteSignerAddress(), podSignerAddress()
        );
        vault = new SettlementVault(manager);
        registry = new CourierRegistry(manager, config, vault);
        reputation = new ReputationRegistry(manager);
        referral = new Referral(manager);
        hub = new DeliveryHub(manager, config, registry, vault, reputation, referral, BID_DEPOSIT);

        pool = new JurorPool(manager, config);
        rng = new SilentRandomness();
        committee = new FallbackCommittee(manager, address(0xBEEF));
        court = new DisputeCourt(manager, config, pool, IRandomnessAdapter(address(rng)), referral, hub, committee);

        vm.startPrank(admin);
        manager.grantRole(manager.VAULT_CONTROLLER_ROLE(), address(registry));
        manager.grantRole(manager.VAULT_CONTROLLER_ROLE(), address(hub));
        manager.grantRole(manager.REGISTRY_CONTROLLER_ROLE(), address(hub));
        manager.grantRole(manager.REPUTATION_REPORTER_ROLE(), address(hub));
        manager.grantRole(manager.REFERRAL_REPORTER_ROLE(), address(hub));
        manager.grantRole(manager.DISPUTE_COURT_ROLE(), address(court));
        vm.stopPrank();

        vm.deal(customer, 1_000 ether);
        vm.deal(courier, 1_000 ether);
        uint256 stakeAmount = config.courierBaseDeposit() + 40 ether;
        vm.prank(courier);
        registry.depositStake{value: stakeAmount}();
    }

    // ------------------------------------------------------------ helpers

    function _created(address who) internal returns (uint256 id) {
        CoverageQuote.Quote memory q = buildQuote(config, who, 1, DECLARED_VALUE);
        bytes memory qsig = signQuote(hub, q);
        vm.prank(who);
        id = hub.createDelivery(q, qsig);
    }

    function _selected(address who) internal returns (uint256 id) {
        id = _created(who);
        vm.prank(courier);
        hub.placeBid(id, ASK, RETURN_ASK, 30, uint64(block.timestamp + 1 hours));
        uint32 version = hub.bidOf(id, courier).termsVersion;
        vm.prank(who);
        hub.selectCourier(id, courier, version);
    }

    function _inTransit() internal returns (uint256 id) {
        id = _selected(customer);
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

    function _deliveredPending() internal returns (uint256 id) {
        id = _inTransit();
        DeliveryProof.Attestation memory a = buildAttestation(config, id, courier);
        bytes memory sig = signAttestation(hub, a);
        vm.prank(courier);
        hub.submitDeliveryProof(id, a, sig);
    }

    // ------------------------------------------- sec. 33-5

    /**
     * @dev Invariant sec. 33-5. The court holds the delivery, so the ordinary
     *      success path has to be closed — otherwise a customer who did not like
     *      where the jury was heading could simply confirm the delivery and pay
     *      the courier behind its back, or a permissionless `poke` could do it
     *      for them once the challenge window lapsed.
     *
     *      The state machine is what closes it, and this pins that: `Disputed`
     *      is not `DeliveredPending`, so every route into `_complete` is refused.
     */
    function test_Invariant33_5_ADisputedDeliveryCannotSettleThroughSuccess() public {
        uint256 id = _deliveredPending();

        uint256 cost = uint256(config.arbitrationFee(1)) + config.disputeBond(1);
        vm.prank(customer);
        court.open{value: cost}(id);
        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.Disputed));

        vm.expectRevert(
            abi.encodeWithSelector(
                DeliveryHub.WrongState.selector, id, DeliveryHub.State.Disputed, DeliveryHub.State.DeliveredPending
            )
        );
        vm.prank(customer);
        hub.confirmDelivery(id);

        // And the clock cannot complete it either: the long stop is the only
        // deadline left, and it resolves, it does not succeed.
        // Deadline read before the cheatcode: `deliveryOf` is a call, and a call
        // inside the argument expression is evaluated after `vm.expectRevert`
        // arms and consumes it.
        uint64 longStop = hub.deliveryOf(id).stateDeadline;
        vm.warp(block.timestamp + config.challengeWindow() + 1);
        vm.expectRevert(abi.encodeWithSelector(DeliveryHub.DeadlineNotReached.selector, longStop));
        hub.poke(id);

        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.Disputed), "still the court's");
        assertEq(vault.claimableOf(courier), 0, "and the courier was paid nothing");
    }

    // ------------------------------------------- sec. 33-9

    /**
     * @dev Invariant sec. 33-9: the collateral that answers for the goods is in
     *      place before anyone takes custody of them. Structural rather than a
     *      check — `confirmPickup` only accepts `ReadyForPickup`, which needs
     *      both sides funded — but the invariant is worth a test of its own,
     *      because "structural" is a claim about code that can be refactored.
     */
    function test_Invariant33_9_PickupIsImpossibleBeforeCollateralIsLocked() public {
        uint256 id = _selected(customer);
        uint256 amount = hub.customerFundingAmount(id);
        vm.prank(customer);
        hub.fundAsCustomer{value: amount}(id);

        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.AwaitingFunding), "courier has not funded");

        PickupProof.Acceptance memory acc = buildAcceptance(id, courier);
        bytes memory asig = signAcceptance(hub, acc, senderKey(0));

        vm.expectRevert(
            abi.encodeWithSelector(
                DeliveryHub.WrongState.selector, id, DeliveryHub.State.AwaitingFunding, DeliveryHub.State.ReadyForPickup
            )
        );
        vm.prank(courier);
        hub.confirmPickup(id, acc, asig);

        assertEq(registry.courierOf(courier).activeCustody, 0, "nobody took custody");

        // Funding it makes the same call succeed, so the refusal was about the
        // collateral and not about something else in the acceptance.
        vm.prank(courier);
        hub.fundAsCourier(id);
        vm.prank(courier);
        hub.confirmPickup(id, acc, asig);
        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.InTransit));
    }

    // ------------------------------------------ sec. 33-11 / sec. 47

    /**
     * @dev Invariant sec. 33-11 at the level that matters. `SettlementVault`
     *      proves a reverting account cannot block a *release*; this proves the
     *      same for a whole delivery, where the reverting party is the customer
     *      the refund is owed to.
     *
     *      sec. 18.2's pull model is the mechanism: settlement credits, it never
     *      sends. So the courier and the treasury are paid, and the customer's
     *      share waits in `claimable` for a wallet that can take it.
     */
    function test_Failure_ARejectingCustomerCannotBlockAnybodysSettlement() public {
        RejectingWallet wallet = new RejectingWallet();
        vm.deal(address(wallet), 1_000 ether);

        uint256 id = _selected(address(wallet));
        uint256 amount = hub.customerFundingAmount(id);
        wallet.call{value: amount}(address(hub), abi.encodeCall(DeliveryHub.fundAsCustomer, (id)));
        vm.prank(courier);
        hub.fundAsCourier(id);

        // The wallet cannot sign, so the delivery reaches its end by the clock.
        vm.warp(block.timestamp + config.pickupWindow() + 1);
        hub.poke(id);

        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.Cancelled), "settled anyway");
        assertEq(vault.claimableOf(address(wallet)), amount, "the refund is held, not lost");
        assertEq(registry.courierOf(courier).reserved, 0, "and the courier is free");

        // The money is genuinely stuck to the wallet, not to the protocol: a
        // claim reverts, and everyone else's is unaffected.
        vm.expectRevert();
        wallet.call(address(vault), abi.encodeCall(SettlementVault.claim, ()));
        assertEq(vault.claimableOf(address(wallet)), amount, "still owed");
    }

    // -------------------------------------------------------- sec. 47

    /// @dev sec. 47: the customer selects a courier and then simply never funds.
    function test_Failure_CustomerSelectsButNeverFunds() public {
        uint256 id = _selected(customer);
        assertEq(registry.courierOf(courier).reserved, BID_DEPOSIT, "the bid deposit is held");

        vm.warp(block.timestamp + config.fundingWindow() + 1);
        hub.poke(id);

        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.Cancelled));
        assertEq(registry.courierOf(courier).reserved, 0, "the courier does not pay for the customer's silence");
        assertEq(vault.claimableOf(customer), 0, "nothing was escrowed, so nothing is owed");
    }

    /// @dev sec. 47: the customer funds and the courier never posts coverage.
    function test_Failure_CourierNeverProvidesCoverage() public {
        uint256 id = _selected(customer);
        uint256 amount = hub.customerFundingAmount(id);
        vm.prank(customer);
        hub.fundAsCustomer{value: amount}(id);

        vm.warp(block.timestamp + config.fundingWindow() + 1);
        hub.poke(id);

        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.Cancelled));
        assertEq(vault.claimableOf(customer), amount, "the customer's escrow comes back in full");
        assertEq(registry.courierOf(courier).reserved, 0, "and the bid deposit is released");
    }

    /**
     * @dev sec. 47: a return is asked for and never confirmed. sec. 17's answer
     *      is deterministic — the customer is made whole and the coverage is
     *      released unslashed, because slashing needs a finding and a silent
     *      courier is not one (sec. 13, sec. 26).
     */
    function test_Failure_ReturnIsAskedForAndNeverConfirmed() public {
        uint256 id = _inTransit();
        uint256 total = hub.customerFundingAmount(id);

        vm.prank(customer);
        hub.requestReturn(id);
        vm.warp(block.timestamp + config.returnWindow() + 1);
        hub.poke(id);

        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.Returned));
        assertEq(vault.claimableOf(customer), total, "no return fee for a return nobody confirmed");
        assertEq(vault.claimableOf(courier), 0);
        assertEq(registry.courierOf(courier).reserved, 0, "coverage released, not slashed");
        assertEq(registry.courierOf(courier).activeCustody, 0);
    }

    /**
     * @dev sec. 47: the recipient is unavailable, so nobody confirms. sec. 16's
     *      challenge window closes on its own and anyone may finalise, which is
     *      what stops an absent recipient from holding the courier's fee.
     */
    function test_Failure_NobodyConfirmsSoTheWindowFinalisesIt() public {
        uint256 id = _deliveredPending();
        address stranger = address(0x5747A);

        vm.warp(block.timestamp + config.challengeWindow() + 1);
        vm.prank(stranger);
        hub.poke(id);

        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.Completed));
        assertEq(vault.claimableOf(courier), ASK, "the courier is paid without anyone's permission");
        assertEq(vault.claimableOf(customer), RETURN_ASK, "and the unused return reserve goes back");
    }
}
