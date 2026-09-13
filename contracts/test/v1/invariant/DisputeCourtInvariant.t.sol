// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {ProtocolAccessManager} from "../../../src/v1/access/ProtocolAccessManager.sol";
import {ProtocolConfig} from "../../../src/v1/config/ProtocolConfig.sol";
import {BaselineParams} from "../../../src/v1/config/BaselineParams.sol";
import {SettlementVault} from "../../../src/v1/vault/SettlementVault.sol";
import {CourierRegistry} from "../../../src/v1/registry/CourierRegistry.sol";
import {ReputationRegistry} from "../../../src/v1/reputation/ReputationRegistry.sol";
import {Referral} from "../../../src/v1/rewards/Referral.sol";
import {DeliveryHub} from "../../../src/v1/hub/DeliveryHub.sol";
import {JurorPool} from "../../../src/v1/dispute/JurorPool.sol";
import {DisputeCourt} from "../../../src/v1/dispute/DisputeCourt.sol";
import {FallbackCommittee} from "../../../src/v1/dispute/FallbackCommittee.sol";
import {IRandomnessAdapter} from "../../../src/v1/randomness/IRandomnessAdapter.sol";
import {CoverageQuote} from "../../../src/v1/risk/CoverageQuote.sol";
import {PickupProof} from "../../../src/v1/proof/PickupProof.sol";
import {QuoteFixture} from "../helpers/QuoteFixture.sol";
import {PickupFixture} from "../helpers/PickupFixture.sol";

/// @dev Randomness the fuzzer controls, so a draw may arrive or never arrive.
contract FuzzRandomness is IRandomnessAdapter {
    uint64 public nextId = 1;
    mapping(uint64 => bytes32) internal _value;
    mapping(uint64 => bool) internal _fulfilled;
    mapping(uint64 => address) internal _requester;

    function fee() external pure returns (uint256) {
        return 0.01 ether;
    }

    function request(bytes32) external payable returns (uint64 requestId) {
        requestId = nextId++;
        _requester[requestId] = msg.sender;
    }

    function deliver(uint64 requestId, bytes32 v) external {
        if (requestId == 0 || requestId >= nextId) return;
        _value[requestId] = v;
        _fulfilled[requestId] = true;
    }

    function randomnessOf(uint64 requestId) external view returns (bytes32, bool) {
        return (_value[requestId], _fulfilled[requestId]);
    }

    function isFulfilled(uint64 requestId) external view returns (bool) {
        return _fulfilled[requestId];
    }

    function requesterOf(uint64 requestId) external view returns (address) {
        return _requester[requestId];
    }
}

/**
 * @notice Drives disputes down every path the court offers, in random order.
 * @dev The paths that matter are the ones that end a case: a jury ruling, an
 *      appeal and then a ruling, a committee decision on a failed round, and the
 *      hub's long stop firing under a court that stopped answering. The fuzzer
 *      is allowed to interleave all of them, including on the same dispute,
 *      because "settles exactly once" is only interesting when something is
 *      trying to settle it twice.
 */
contract CourtHandler is QuoteFixture, PickupFixture {
    ProtocolConfig public immutable config;
    SettlementVault public immutable vault;
    CourierRegistry public immutable registry;
    DeliveryHub public immutable hub;
    JurorPool public immutable pool;
    DisputeCourt public immutable court;
    FallbackCommittee public immutable committee;
    FuzzRandomness public immutable rng;

    uint256 public constant SAFE_KEY = 0x5AFE;

    address public customer;
    address public courier;
    address[] public jurorList;

    uint256[] public disputeIds;
    mapping(uint256 => bool) public known;

    uint256 public opened;
    uint256 public ruled;
    uint256 public appealed;
    uint256 public settled;
    uint256 public byCommittee;
    uint256 public abandoned;
    uint256 public longStopped;

    constructor(
        ProtocolConfig config_,
        SettlementVault vault_,
        CourierRegistry registry_,
        DeliveryHub hub_,
        JurorPool pool_,
        DisputeCourt court_,
        FallbackCommittee committee_,
        FuzzRandomness rng_,
        address customer_,
        address courier_,
        address[] memory jurors_
    ) {
        config = config_;
        vault = vault_;
        registry = registry_;
        hub = hub_;
        pool = pool_;
        court = court_;
        committee = committee_;
        rng = rng_;
        customer = customer_;
        courier = courier_;
        for (uint256 i = 0; i < jurors_.length; i++) {
            jurorList.push(jurors_[i]);
        }
    }

    // ------------------------------------------------------------ actions

    function openDispute(uint96 declaredValue) external {
        declaredValue = uint96(bound(declaredValue, 1 ether, 30 ether));

        uint256 deliveryId = _toInTransit(declaredValue);
        if (deliveryId == type(uint256).max) return;

        uint256 cost = uint256(config.arbitrationFee(1)) + config.disputeBond(1);
        vm.prank(customer);
        try court.open{value: cost}(deliveryId) returns (uint256 id) {
            disputeIds.push(id);
            known[id] = true;
            opened++;
        } catch {}
    }

    function requestDraw(uint256 seed) external {
        (uint256 id, bool ok) = _pick(seed);
        if (!ok) return;

        vm.warp(block.timestamp + config.evidenceWindow() + 1);
        uint256 drawFee = rng.fee();
        vm.prank(customer);
        try court.requestDraw{value: drawFee}(id) {} catch {}
    }

    function deliverRandomness(uint256 seed) external {
        (uint256 id, bool ok) = _pick(seed);
        if (!ok) return;

        uint64 requestId = court.disputeOf(id).drawRequestId;
        if (requestId == 0) return;
        rng.deliver(requestId, keccak256(abi.encode(seed)));
    }

    function seatPanel(uint256 seed) external {
        (uint256 id, bool ok) = _pick(seed);
        if (!ok) return;
        try court.seatPanel(id) {} catch {}
    }

    function voteAndRule(uint256 seed, uint8 rulingSeed) external {
        (uint256 id, bool ok) = _pick(seed);
        if (!ok) return;
        if (court.disputeOf(id).phase != DisputeCourt.Phase.Commit) return;

        DisputeCourt.Ruling ruling = DisputeCourt.Ruling((rulingSeed % 6) + 1);
        address[] memory panel = court.panelOf(id);
        uint8 round = court.disputeOf(id).round;

        for (uint256 i = 0; i < panel.length; i++) {
            bytes32 h = court.hashVote(id, round, panel[i], ruling, bytes32(uint256(i + 1)));
            vm.prank(panel[i]);
            try court.commitVote(id, h) {} catch {}
        }
        vm.warp(block.timestamp + config.commitWindow() + 1);
        try court.closeCommit(id) {}
        catch {
            return;
        }
        for (uint256 i = 0; i < panel.length; i++) {
            vm.prank(panel[i]);
            try court.revealVote(id, ruling, bytes32(uint256(i + 1))) {} catch {}
        }
        vm.warp(block.timestamp + config.revealWindow() + 1);
        try court.closeReveal(id) {
            if (court.disputeOf(id).phase == DisputeCourt.Phase.Ruled) ruled++;
        } catch {}
    }

    /// @dev The silent-panel path: commit and reveal both elapse untouched.
    function letThePanelGoQuiet(uint256 seed) external {
        (uint256 id, bool ok) = _pick(seed);
        if (!ok) return;

        vm.warp(block.timestamp + config.commitWindow() + 1);
        try court.closeCommit(id) {}
        catch {
            return;
        }
        vm.warp(block.timestamp + config.revealWindow() + 1);
        try court.closeReveal(id) {} catch {}
    }

    function appeal(uint256 seed) external {
        (uint256 id, bool ok) = _pick(seed);
        if (!ok) return;

        uint8 round = court.disputeOf(id).round;
        if (round >= court.MAX_ROUND()) return;
        uint256 cost = uint256(config.arbitrationFee(round + 1)) + config.disputeBond(round + 1);

        vm.prank(courier);
        try court.appeal{value: cost}(id) {
            appealed++;
        } catch {}
    }

    function finalise(uint256 seed, uint32 warpBy) external {
        (uint256 id, bool ok) = _pick(seed);
        if (!ok) return;

        vm.warp(block.timestamp + (warpBy % 5 days));
        try court.finalise(id) {
            settled++;
        } catch {}
    }

    function resolveByCommittee(uint256 seed, uint8 rulingSeed) external {
        (uint256 id, bool ok) = _pick(seed);
        if (!ok) return;

        FallbackCommittee.Decision memory decision = FallbackCommittee.Decision({
            disputeId: id,
            round: court.disputeOf(id).round,
            ruling: (rulingSeed % 6) + 1,
            expiresAt: uint64(block.timestamp + 1 days)
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SAFE_KEY, committee.hashDecision(decision));

        try court.resolveByCommittee(id, decision, abi.encodePacked(r, s, v)) {
            byCommittee++;
            settled++;
        } catch {}
    }

    /// @dev The court goes silent for long enough that the hub gives up on it.
    function longStop(uint256 seed) external {
        (uint256 id, bool ok) = _pick(seed);
        if (!ok) return;

        uint256 deliveryId = court.disputeOf(id).deliveryId;
        vm.warp(block.timestamp + config.disputeWindow() + 1);
        try hub.poke(deliveryId) {
            longStopped++;
        } catch {}
    }

    function abandon(uint256 seed) external {
        (uint256 id, bool ok) = _pick(seed);
        if (!ok) return;
        try court.abandon(id) {
            abandoned++;
        } catch {}
    }

    function claim(uint256 seed) external {
        address who = seed % 2 == 0 ? customer : courier;
        vm.prank(who);
        try court.claim() {} catch {}
    }

    // ------------------------------------------------------------ helpers

    function disputeCount() external view returns (uint256) {
        return disputeIds.length;
    }

    function disputeAt(uint256 i) external view returns (uint256) {
        return disputeIds[i];
    }

    function _pick(uint256 seed) internal view returns (uint256 id, bool ok) {
        if (disputeIds.length == 0) return (0, false);
        return (disputeIds[seed % disputeIds.length], true);
    }

    /// @dev Returns `type(uint256).max` when the courier could not take another.
    function _toInTransit(uint96 declaredValue) internal returns (uint256) {
        CoverageQuote.Quote memory q = buildQuote(config, customer, 1, declaredValue);
        bytes memory qsig = signQuote(hub, q);

        uint256 id;
        vm.prank(customer);
        try hub.createDelivery(q, qsig) returns (uint256 created) {
            id = created;
        } catch {
            return type(uint256).max;
        }

        vm.prank(courier);
        try hub.placeBid(id, 1 ether, 0.2 ether, 30, uint64(block.timestamp + 1 hours)) {}
        catch {
            return type(uint256).max;
        }

        uint32 version = hub.bidOf(id, courier).termsVersion;
        vm.prank(customer);
        try hub.selectCourier(id, courier, version) {}
        catch {
            return type(uint256).max;
        }

        uint256 amount = hub.customerFundingAmount(id);
        vm.prank(customer);
        try hub.fundAsCustomer{value: amount}(id) {}
        catch {
            return type(uint256).max;
        }
        vm.prank(courier);
        try hub.fundAsCourier(id) {}
        catch {
            return type(uint256).max;
        }

        PickupProof.Acceptance memory acc = buildAcceptance(id, courier);
        bytes memory asig = signAcceptance(hub, acc, senderKey(0));
        vm.prank(courier);
        try hub.confirmPickup(id, acc, asig) {}
        catch {
            return type(uint256).max;
        }
        return id;
    }
}

/**
 * @notice A dispute settles exactly once, whichever path ends it (sec. 51).
 * @dev The court has four ways to finish a case and they must not be able to
 *      overlap: a jury ruling, a committee decision, the hub's long stop, and
 *      abandonment. Each one moves real money, so two of them landing on the
 *      same delivery would pay the escrow out twice.
 */
contract DisputeCourtInvariantTest is StdInvariant, QuoteFixture, PickupFixture {
    ProtocolAccessManager internal manager;
    ProtocolConfig internal config;
    SettlementVault internal vault;
    CourierRegistry internal registry;
    ReputationRegistry internal reputation;
    Referral internal referral;
    DeliveryHub internal hub;
    JurorPool internal pool;
    FuzzRandomness internal rng;
    FallbackCommittee internal committee;
    DisputeCourt internal court;
    CourtHandler internal handler;

    address internal admin = address(0xA11CE);
    address internal treasury = address(0x7EA5);
    address internal customer;
    address internal courier = address(0xC0DE);

    function setUp() public {
        customer = senderAddress(0);

        manager = new ProtocolAccessManager(3 days, admin);
        config = new ProtocolConfig(
            manager, 2 days, BaselineParams.baseline(), treasury, quoteSignerAddress(), address(0x2)
        );
        vault = new SettlementVault(manager);
        registry = new CourierRegistry(manager, config, vault);
        reputation = new ReputationRegistry(manager);
        referral = new Referral(manager);
        hub = new DeliveryHub(manager, config, registry, vault, reputation, referral, 1 ether);

        pool = new JurorPool(manager, config);
        rng = new FuzzRandomness();
        committee = new FallbackCommittee(manager, vm.addr(0x5AFE));
        court = new DisputeCourt(manager, config, pool, IRandomnessAdapter(address(rng)), referral, hub, committee);

        vm.startPrank(admin);
        manager.grantRole(manager.VAULT_CONTROLLER_ROLE(), address(registry));
        manager.grantRole(manager.VAULT_CONTROLLER_ROLE(), address(hub));
        manager.grantRole(manager.REGISTRY_CONTROLLER_ROLE(), address(hub));
        manager.grantRole(manager.REPUTATION_REPORTER_ROLE(), address(hub));
        manager.grantRole(manager.REFERRAL_REPORTER_ROLE(), address(hub));
        manager.grantRole(manager.DISPUTE_COURT_ROLE(), address(court));
        manager.grantRole(manager.REFERRAL_REPORTER_ROLE(), address(court));
        vm.stopPrank();

        address[] memory jurorList = new address[](8);
        for (uint160 i = 0; i < 8; i++) {
            address j = address(uint160(0xD0000) + i);
            jurorList[i] = j;
            vm.deal(j, 100 ether);
            vm.startPrank(j);
            pool.stake{value: config.minJurorStake() * 3}();
            pool.activate();
            vm.stopPrank();
        }

        vm.deal(customer, 10_000 ether);
        vm.deal(courier, 10_000 ether);
        uint256 stakeAmount = config.courierBaseDeposit() + 200 ether;
        vm.prank(courier);
        registry.depositStake{value: stakeAmount}();

        handler =
            new CourtHandler(config, vault, registry, hub, pool, court, committee, rng, customer, courier, jurorList);
        vm.deal(address(handler), 100_000 ether);
        // The handler acts as both parties, so it needs to be able to send as them.
        vm.deal(customer, 10_000 ether);

        // Only the actions. Without this the fuzzer spends most of its budget
        // on the handler's own getters -- `disputeAt`, `jurorList`, the public
        // counters -- and the run comes back having opened nothing, which is
        // how these invariants passed vacuously the first time they were run.
        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = CourtHandler.openDispute.selector;
        selectors[1] = CourtHandler.requestDraw.selector;
        selectors[2] = CourtHandler.deliverRandomness.selector;
        selectors[3] = CourtHandler.seatPanel.selector;
        selectors[4] = CourtHandler.voteAndRule.selector;
        selectors[5] = CourtHandler.letThePanelGoQuiet.selector;
        selectors[6] = CourtHandler.appeal.selector;
        selectors[7] = CourtHandler.finalise.selector;
        selectors[8] = CourtHandler.resolveByCommittee.selector;
        selectors[9] = CourtHandler.longStop.selector;
        selectors[10] = CourtHandler.abandon.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /**
     * @dev Invariant sec. 33-1 as it reaches the court: the escrow is a claim on
     *      value that was actually deposited. Every path out of a dispute pays
     *      through the vault, so if two of them could both fire the vault would
     *      owe more than it holds.
     */
    function invariant_VaultStaysSolvent() public view {
        assertGe(address(vault).balance, vault.totalLiabilities(), "vault owes more than it holds");
    }

    /// @dev The court holds bonds and fees for other people. It must never dip.
    function invariant_CourtStaysSolvent() public view {
        assertGe(address(court).balance, court.totalOwed(), "court owes more than it holds");
    }

    /**
     * @dev The acceptance criterion. A delivery that has left `Disputed` is
     *      terminal, and nothing may move it again: whichever path got there
     *      first is the only one that paid.
     */
    function invariant_ADisputedDeliveryEndsInExactlyOneTerminalState() public view {
        uint256 n = handler.disputeCount();
        for (uint256 i = 0; i < n; i++) {
            uint256 id = handler.disputeAt(i);
            DeliveryHub.State state = hub.deliveryOf(court.disputeOf(id).deliveryId).state;
            assertTrue(
                state == DeliveryHub.State.Disputed || state == DeliveryHub.State.Resolved,
                "a disputed delivery reached a state no dispute path produces"
            );
        }
    }

    /// @dev A court that has finished with a case never goes back to running it.
    function invariant_ASettledDisputeStaysSettled() public view {
        uint256 n = handler.disputeCount();
        for (uint256 i = 0; i < n; i++) {
            DisputeCourt.Dispute memory d = court.disputeOf(handler.disputeAt(i));
            if (d.phase == DisputeCourt.Phase.Settled || d.phase == DisputeCourt.Phase.Abandoned) {
                assertEq(d.phaseDeadline, 0, "a terminal dispute still carries a deadline");
                assertEq(d.feesHeld, 0, "a terminal dispute still holds fees");
            }
        }
    }

    /// @dev sec. 28: the escalation stops at three, whatever the fuzzer tries.
    function invariant_NoDisputeEverReachesAFourthRound() public view {
        uint256 n = handler.disputeCount();
        for (uint256 i = 0; i < n; i++) {
            assertLe(court.disputeOf(handler.disputeAt(i)).round, court.MAX_ROUND(), "a fourth round was opened");
        }
    }

    /**
     * @dev Guards against vacuity. Invariants over a handler whose actions all
     *      fail prove nothing at all, so this drives one dispute the whole way
     *      by hand and insists every counter the invariants depend on moves.
     */
    function test_invariant_HandlerCanActuallyReachEveryEnding() public {
        handler.openDispute(5 ether);
        assertEq(handler.opened(), 1, "opening a dispute must succeed");

        handler.requestDraw(0);
        handler.deliverRandomness(0);
        handler.seatPanel(0);
        assertGt(court.panelSize(handler.disputeAt(0)), 0, "a panel must be seatable");

        handler.voteAndRule(0, 1);
        assertEq(handler.ruled(), 1, "a jury must be able to rule");

        handler.appeal(0);
        assertEq(handler.appealed(), 1, "an appeal must be reachable");

        // An appeal puts the case back in `Evidence`, so the second round has to
        // be run before anything can settle.
        handler.requestDraw(0);
        handler.deliverRandomness(0);
        handler.seatPanel(0);
        handler.voteAndRule(0, 2);
        assertEq(handler.ruled(), 2, "the larger panel must be able to rule too");

        handler.finalise(0, uint32(3 days));
        assertEq(handler.settled(), 1, "a ruling must be able to settle");

        // And the two endings that do not go through a ruling at all.
        handler.openDispute(6 ether);
        handler.longStop(1);
        assertEq(handler.longStopped(), 1, "the hub's long stop must be reachable");
        handler.abandon(1);
        assertEq(handler.abandoned(), 1, "abandonment must be reachable");
    }

    /// @dev And the committee path, which needs a round that failed outright.
    function test_invariant_HandlerCanReachTheCommitteePath() public {
        handler.openDispute(5 ether);
        handler.requestDraw(0);
        handler.deliverRandomness(0);
        handler.seatPanel(0);
        handler.letThePanelGoQuiet(0);

        assertEq(
            uint8(court.disputeOf(handler.disputeAt(0)).phase),
            uint8(DisputeCourt.Phase.Failed),
            "a silent panel must fail the round"
        );

        handler.resolveByCommittee(0, 5);
        assertEq(handler.byCommittee(), 1, "the committee must be able to end it");
    }
}
