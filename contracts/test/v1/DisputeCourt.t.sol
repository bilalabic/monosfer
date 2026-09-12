// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProtocolAccessManager} from "../../src/v1/access/ProtocolAccessManager.sol";
import {ProtocolConfig} from "../../src/v1/config/ProtocolConfig.sol";
import {BaselineParams} from "../../src/v1/config/BaselineParams.sol";
import {JurorPool} from "../../src/v1/dispute/JurorPool.sol";
import {Referral} from "../../src/v1/rewards/Referral.sol";
import {DisputeCourt} from "../../src/v1/dispute/DisputeCourt.sol";
import {IRandomnessAdapter} from "../../src/v1/randomness/IRandomnessAdapter.sol";
import {FallbackCommittee} from "../../src/v1/dispute/FallbackCommittee.sol";
import {SettlementVault} from "../../src/v1/vault/SettlementVault.sol";
import {CourierRegistry} from "../../src/v1/registry/CourierRegistry.sol";
import {ReputationRegistry} from "../../src/v1/reputation/ReputationRegistry.sol";
import {DeliveryHub} from "../../src/v1/hub/DeliveryHub.sol";
import {CoverageQuote} from "../../src/v1/risk/CoverageQuote.sol";
import {PickupProof} from "../../src/v1/proof/PickupProof.sol";
import {QuoteFixture} from "./helpers/QuoteFixture.sol";
import {PickupFixture} from "./helpers/PickupFixture.sol";

/// @dev A randomness adapter under the test's control, so a draw can be made to
///      arrive, be delayed forever, or land on a chosen value.
contract StubRandomness is IRandomnessAdapter {
    uint256 public feeAmount = 0.05 ether;
    uint64 public nextId = 1;
    mapping(uint64 => bytes32) internal _value;
    mapping(uint64 => bool) internal _fulfilled;
    mapping(uint64 => address) internal _requester;

    function setFee(uint256 f) external {
        feeAmount = f;
    }

    function fee() external view returns (uint256) {
        return feeAmount;
    }

    function request(bytes32) external payable returns (uint64 requestId) {
        require(msg.value == feeAmount, "fee not passed through");
        requestId = nextId++;
        _requester[requestId] = msg.sender;
        emit RandomnessRequested(requestId, msg.sender, msg.value);
    }

    function deliver(uint64 requestId, bytes32 v) external {
        _value[requestId] = v;
        _fulfilled[requestId] = true;
        emit RandomnessRecorded(requestId, v);
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
 * @notice The dispute court (sec. 26, sec. 28, sec. 30).
 * @dev Three invariants carry this suite: a juror never takes two seats on one
 *      panel (sec. 33-13), a juror who reveals a losing vote is never slashed
 *      (sec. 33-14), and a draw already requested cannot be steered (sec. 33-18).
 */
/// @dev A contract wallet that approves exactly one digest, so the ERC-1271 leg
///      of sec. 31 is exercised against something that is not an EOA.
contract StubSafe {
    mapping(bytes32 => bool) public approved;

    function approve(bytes32 digest) external {
        approved[digest] = true;
    }

    function isValidSignature(bytes32 digest, bytes calldata) external view returns (bytes4) {
        return approved[digest] ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
    }
}

contract DisputeCourtTest is QuoteFixture, PickupFixture {
    ProtocolAccessManager internal manager;
    ProtocolConfig internal config;
    JurorPool internal pool;
    Referral internal referral;
    StubRandomness internal rng;
    DisputeCourt internal court;
    FallbackCommittee internal committee;
    SettlementVault internal vault;
    CourierRegistry internal registry;
    ReputationRegistry internal reputation;
    DeliveryHub internal hub;

    address internal admin = address(0xA11CE);
    address internal treasury = address(0x7EA5);
    address internal configAdmin = address(0xC0F1);
    address internal signerAdmin = address(0x5164E);
    address internal outsider = address(0xBAD);

    address internal customer;
    address internal courier = address(0xC0DE);

    uint256 internal constant SAFE_KEY = 0x5AFE;
    address internal safeSigner;

    uint96 internal constant BID_DEPOSIT = 1 ether;
    uint96 internal constant DECLARED_VALUE = 20 ether;
    uint96 internal constant ASK = 10 ether;
    uint96 internal constant RETURN_ASK = 2 ether;

    uint256 internal MIN;
    uint256 internal SLASH;

    address[] internal jurorList;

    function setUp() public {
        customer = senderAddress(0);
        safeSigner = vm.addr(SAFE_KEY);

        manager = new ProtocolAccessManager(3 days, admin);
        config = new ProtocolConfig(
            manager, 2 days, BaselineParams.baseline(), treasury, quoteSignerAddress(), address(0x2)
        );
        vault = new SettlementVault(manager);
        registry = new CourierRegistry(manager, config, vault);
        reputation = new ReputationRegistry(manager);
        referral = new Referral(manager);
        hub = new DeliveryHub(manager, config, registry, vault, reputation, referral, BID_DEPOSIT);

        pool = new JurorPool(manager, config);
        rng = new StubRandomness();
        committee = new FallbackCommittee(manager, safeSigner);
        court = new DisputeCourt(manager, config, pool, IRandomnessAdapter(address(rng)), referral, hub, committee);

        vm.startPrank(admin);
        manager.grantRole(manager.DISPUTE_COURT_ROLE(), address(court));
        manager.grantRole(manager.REFERRAL_REPORTER_ROLE(), address(court));
        manager.grantRole(manager.CONFIG_ADMIN_ROLE(), configAdmin);
        manager.grantRole(manager.SIGNER_ADMIN_ROLE(), signerAdmin);
        manager.grantRole(manager.VAULT_CONTROLLER_ROLE(), address(registry));
        manager.grantRole(manager.VAULT_CONTROLLER_ROLE(), address(hub));
        manager.grantRole(manager.REGISTRY_CONTROLLER_ROLE(), address(hub));
        manager.grantRole(manager.REPUTATION_REPORTER_ROLE(), address(hub));
        manager.grantRole(manager.REFERRAL_REPORTER_ROLE(), address(hub));
        vm.stopPrank();

        MIN = config.minJurorStake();
        SLASH = config.nonRevealSlash();

        vm.deal(customer, 1_000 ether);
        vm.deal(courier, 1_000 ether);
        uint256 stakeAmount = config.courierBaseDeposit() + 40 ether;
        vm.prank(courier);
        registry.depositStake{value: stakeAmount}();

        for (uint160 i = 0; i < 16; i++) {
            address j = address(uint160(0xD0000) + i);
            jurorList.push(j);
        }
    }

    // ------------------------------------------------------------ helpers

    function _addJurors(uint256 n) internal {
        for (uint256 i = 0; i < n; i++) {
            address j = jurorList[i];
            vm.deal(j, MIN * 2);
            vm.startPrank(j);
            pool.stake{value: MIN * 2}();
            pool.activate();
            vm.stopPrank();
        }
    }

    /// @dev A delivery in `InTransit`: funded, picked up, and disputable.
    function _disputableDelivery() internal returns (uint256 deliveryId) {
        CoverageQuote.Quote memory q = buildQuote(config, customer, 1, DECLARED_VALUE);
        bytes memory qsig = signQuote(hub, q);
        vm.prank(customer);
        deliveryId = hub.createDelivery(q, qsig);

        vm.prank(courier);
        hub.placeBid(deliveryId, ASK, RETURN_ASK, 30, uint64(block.timestamp + 1 hours));
        uint32 version = hub.bidOf(deliveryId, courier).termsVersion;
        vm.prank(customer);
        hub.selectCourier(deliveryId, courier, version);

        uint256 amount = hub.customerFundingAmount(deliveryId);
        vm.prank(customer);
        hub.fundAsCustomer{value: amount}(deliveryId);
        vm.prank(courier);
        hub.fundAsCourier(deliveryId);

        PickupProof.Acceptance memory acc = buildAcceptance(deliveryId, courier);
        bytes memory asig = signAcceptance(hub, acc, senderKey(0));
        vm.prank(courier);
        hub.confirmPickup(deliveryId, acc, asig);
    }

    /// @dev Opens a paid dispute over a fresh delivery, as the customer.
    function _open() internal returns (uint256 id) {
        uint256 deliveryId = _disputableDelivery();
        uint256 cost = _roundCost(1);
        vm.prank(customer);
        id = court.open{value: cost}(deliveryId);
    }

    function _roundCost(uint8 round) internal view returns (uint256) {
        return uint256(config.arbitrationFee(round)) + config.disputeBond(round);
    }

    function _openAndSeat() internal returns (uint256 id) {
        id = _open();

        vm.warp(block.timestamp + config.evidenceWindow() + 1);
        uint256 drawFee = rng.fee();
        vm.prank(customer);
        court.requestDraw{value: drawFee}(id);

        rng.deliver(court.disputeOf(id).drawRequestId, keccak256("random"));
        court.seatPanel(id);
    }

    function _commit(uint256 id, address juror, DisputeCourt.Ruling r, bytes32 salt) internal {
        bytes32 h = court.hashVote(id, court.disputeOf(id).round, juror, r, salt);
        vm.prank(juror);
        court.commitVote(id, h);
    }

    // --------------------------------------------------------- the lifecycle

    function test_OpenStartsInEvidence() public {
        uint256 deliveryId = _disputableDelivery();
        // Cost read before the cheatcode: `_roundCost` reads config, and a call
        // inside the `{value:}` expression is evaluated after `vm.prank` and
        // consumes it.
        uint256 cost = _roundCost(1);
        vm.prank(customer);
        uint256 id = court.open{value: cost}(deliveryId);

        DisputeCourt.Dispute memory d = court.disputeOf(id);
        assertEq(uint8(d.phase), uint8(DisputeCourt.Phase.Evidence));
        assertEq(d.deliveryId, deliveryId);
        assertEq(d.round, 1);
        assertEq(uint8(hub.deliveryOf(deliveryId).state), uint8(DeliveryHub.State.Disputed), "the hub let go of it");
    }

    /// @dev sec. 34: only a commitment reaches the chain, never the material.
    function test_EvidenceIsOnlyAHash() public {
        uint256 id = _open();

        bytes32 commitment = keccak256("photo of the doorstep");
        vm.prank(customer);
        court.submitEvidence(id, commitment);
        assertEq(court.evidenceOf(id, customer), commitment);
    }

    function test_EvidenceClosesOnTime() public {
        uint256 id = _open();
        vm.warp(block.timestamp + config.evidenceWindow() + 1);

        vm.prank(customer);
        vm.expectRevert();
        court.submitEvidence(id, keccak256("late"));
    }

    function test_DrawCannotStartBeforeEvidenceCloses() public {
        _addJurors(4);
        uint256 id = _open();

        vm.prank(customer);
        uint256 drawFee = rng.fee();
        vm.expectRevert();
        court.requestDraw{value: drawFee}(id);
    }

    /// @dev sec. 29: the fee is passed through, the surplus comes back.
    function test_DrawFeeIsPassedThroughAndExcessRefunded() public {
        _addJurors(4);
        uint256 id = _open();
        vm.warp(block.timestamp + config.evidenceWindow() + 1);

        uint256 before = customer.balance;
        uint256 drawFee = rng.fee();
        vm.prank(customer);
        court.requestDraw{value: drawFee + 1 ether}(id);

        assertEq(customer.balance, before - rng.fee(), "only the provider's fee left");
        // The court still holds the round's fee and bond, and nothing beyond them.
        assertEq(address(court).balance, court.totalOwed(), "and the court keeps only what it owes");
        assertEq(court.totalOwed(), _roundCost(1));
    }

    function test_PanelIsSeatedFromTheDraw() public {
        _addJurors(5);
        uint256 id = _openAndSeat();

        assertEq(court.panelSize(id), config.juryFirstSize());
        assertEq(uint8(court.disputeOf(id).phase), uint8(DisputeCourt.Phase.Commit));
    }

    // ------------------------------------------- invariant sec. 33-13

    /**
     * @dev No juror takes two seats on one panel. Checked across many random
     *      values because a walk that repeats is a property of the arithmetic,
     *      not of one draw.
     */
    function testFuzz_NoJurorTakesTwoSeats(bytes32 seed) public {
        _addJurors(5);
        uint256 id = _open();
        vm.warp(block.timestamp + config.evidenceWindow() + 1);
        uint256 drawFee = rng.fee();
        vm.prank(customer);
        court.requestDraw{value: drawFee}(id);
        rng.deliver(court.disputeOf(id).drawRequestId, seed);
        court.seatPanel(id);

        address[] memory panel = court.panelOf(id);
        assertEq(panel.length, config.juryFirstSize());
        for (uint256 i = 0; i < panel.length; i++) {
            for (uint256 k = i + 1; k < panel.length; k++) {
                assertTrue(panel[i] != panel[k], "the same juror was seated twice");
            }
        }
    }

    /// @dev With exactly as many candidates as seats, everyone is seated once.
    function test_ExactlyEnoughCandidatesFillsThePanelWithoutRepeats() public {
        _addJurors(3);
        uint256 id = _openAndSeat();

        address[] memory panel = court.panelOf(id);
        assertEq(panel.length, 3);
        assertTrue(panel[0] != panel[1] && panel[1] != panel[2] && panel[0] != panel[2]);
    }

    /**
     * @dev The claim the stride actually carries is *coverage*, not distinctness
     *      — a repeat is refused by `isSeated` whatever the stride does. Coverage
     *      only becomes observable when the panel needs every candidate there is,
     *      and it can only fail when the candidate count is composite: with 3 or 5
     *      candidates every stride in range is coprime by accident of primality,
     *      so a walk that cycles early would still fill the panel and no test
     *      would notice. Nine candidates for nine seats is the smallest odd,
     *      composite case sec. 28's sizes allow, and it is the one that exercises
     *      the search for a coprime stride at all.
     */
    function testFuzz_AWalkOverACompositeCandidateSetStillReachesEveryone(bytes32 seed) public {
        _setJuryFirstSize(9);
        _addJurors(9);

        uint256 id = _open();
        vm.warp(block.timestamp + config.evidenceWindow() + 1);
        uint256 drawFee = rng.fee();
        vm.prank(customer);
        court.requestDraw{value: drawFee}(id);
        rng.deliver(court.disputeOf(id).drawRequestId, seed);
        court.seatPanel(id);

        address[] memory panel = court.panelOf(id);
        assertEq(panel.length, 9, "a walk that cycles early cannot fill the panel");
        for (uint256 i = 0; i < panel.length; i++) {
            for (uint256 k = i + 1; k < panel.length; k++) {
                assertTrue(panel[i] != panel[k], "the same juror was seated twice");
            }
        }
    }

    /// @dev Moves `juryFirstSize` to `to`, timelock and all.
    /// @dev The appeal sizes move with it: sec. 28 requires each round to be no
    ///      smaller than the last, and `proposeParams` enforces that ordering.
    function _setJuryFirstSize(uint8 to) internal {
        ProtocolConfig.Params memory p = config.params();
        p.juryFirstSize = to;
        p.juryAppeal1Size = to + 2;
        p.juryAppeal2Size = to + 4;
        vm.prank(configAdmin);
        config.proposeParams(p);
        vm.warp(block.timestamp + 2 days);
        vm.prank(configAdmin);
        config.executeParams();
    }

    /**
     * @dev A snapshot that is too small to fill a panel used to divide by zero
     *      rather than say so: `% size` with nobody standing, and `% (size - 1)`
     *      with exactly one. Both are reported as `PanelTooSmall`, which is what
     *      they are.
     */
    function test_ASingleCandidateFailsCleanlyRatherThanPanicking() public {
        _addJurors(1);

        uint256 id = _open();
        vm.warp(block.timestamp + config.evidenceWindow() + 1);
        uint256 drawFee = rng.fee();
        vm.prank(customer);
        court.requestDraw{value: drawFee}(id);
        rng.deliver(court.disputeOf(id).drawRequestId, keccak256("r"));

        vm.expectRevert(abi.encodeWithSelector(DisputeCourt.PanelTooSmall.selector, uint256(1), uint256(3)));
        court.seatPanel(id);
    }

    /// @dev With nobody standing the draw is refused a step earlier still, so no
    ///      randomness is bought for a panel that could never be seated.
    function test_ADrawCannotBeRequestedWithNobodyStanding() public {
        uint256 id = _open();
        vm.warp(block.timestamp + config.evidenceWindow() + 1);
        uint256 drawFee = rng.fee();

        // The pool is told the round key, not the dispute id: each round of a
        // dispute draws its own frozen set.
        uint256 key = uint256(keccak256(abi.encode(id, uint8(1))));
        vm.expectRevert(abi.encodeWithSelector(JurorPool.SnapshotEmpty.selector, key));
        vm.prank(customer);
        court.requestDraw{value: drawFee}(id);
    }

    function test_TooFewCandidatesFailsRatherThanRepeating() public {
        _addJurors(2);
        uint256 id = _open();
        vm.warp(block.timestamp + config.evidenceWindow() + 1);
        uint256 drawFee = rng.fee();
        vm.prank(customer);
        court.requestDraw{value: drawFee}(id);
        rng.deliver(court.disputeOf(id).drawRequestId, keccak256("r"));

        vm.expectRevert(abi.encodeWithSelector(DisputeCourt.PanelTooSmall.selector, uint256(2), uint256(3)));
        court.seatPanel(id);
    }

    // ------------------------------------------- invariant sec. 33-18

    /// @dev Joining after the draw was requested does not get you onto the panel.
    function test_LatecomerCannotJoinAPendingDraw() public {
        _addJurors(3);
        uint256 id = _open();
        vm.warp(block.timestamp + config.evidenceWindow() + 1);
        uint256 drawFee = rng.fee();
        vm.prank(customer);
        court.requestDraw{value: drawFee}(id);

        address latecomer = jurorList[7];
        vm.deal(latecomer, MIN * 2);
        vm.startPrank(latecomer);
        pool.stake{value: MIN * 2}();
        pool.activate();
        vm.stopPrank();

        rng.deliver(court.disputeOf(id).drawRequestId, keccak256("r"));
        court.seatPanel(id);

        address[] memory panel = court.panelOf(id);
        for (uint256 i = 0; i < panel.length; i++) {
            assertTrue(panel[i] != latecomer, "a latecomer reached a draw already under way");
        }
    }

    /**
     * @dev The decisive form of sec. 33-18, and the reason one latecomer is not
     *      enough to prove it: with a live pool a single extra candidate may
     *      simply not be drawn, so the test above can pass against a contract
     *      that froze nothing. Here the *entire* candidate set is replaced after
     *      the draw is requested. A live pool would have nobody left from the
     *      original set to seat and could only fail; a frozen one seats exactly
     *      the three who were standing when the request went in.
     */
    function test_ReplacingTheWholePoolAfterTheRequestChangesNothing() public {
        _addJurors(3);
        address[3] memory original = [jurorList[0], jurorList[1], jurorList[2]];

        uint256 id = _open();
        vm.warp(block.timestamp + config.evidenceWindow() + 1);
        uint256 drawFee = rng.fee();
        vm.prank(customer);
        court.requestDraw{value: drawFee}(id);

        // Everyone who was standing steps down; a fresh set steps up.
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(original[i]);
            pool.deactivate();
        }
        for (uint256 i = 5; i < 8; i++) {
            address newcomer = jurorList[i];
            vm.deal(newcomer, MIN * 2);
            vm.startPrank(newcomer);
            pool.stake{value: MIN * 2}();
            pool.activate();
            vm.stopPrank();
        }
        assertEq(pool.eligibleCount(), 3, "the live pool is now a different set entirely");

        rng.deliver(court.disputeOf(id).drawRequestId, keccak256("r"));
        court.seatPanel(id);

        address[] memory panel = court.panelOf(id);
        assertEq(panel.length, 3);
        for (uint256 i = 0; i < panel.length; i++) {
            assertTrue(
                panel[i] == original[0] || panel[i] == original[1] || panel[i] == original[2],
                "the panel was drawn from the live pool, not the frozen one"
            );
        }
    }

    // ------------------------------------------------ sec. 25: juror rewards

    /**
     * @dev sec. 25 qualifies a juror on a first *finalised* round, so the report
     *      belongs to `closeReveal` and not to commit or reveal. A juror who
     *      committed and then went silent did not serve, and is slashed rather
     *      than rewarded.
     */
    function test_ServingOnAFinalisedPanelQualifiesAJuror() public {
        _addJurors(5);
        uint256 id = _openAndSeat();
        address[] memory panel = court.panelOf(id);

        address silent = panel[2];
        vm.prank(silent);
        referral.register(address(0xBEEF));

        for (uint256 i = 0; i < panel.length; i++) {
            _commit(id, panel[i], DisputeCourt.Ruling.Customer100, bytes32(uint256(i + 1)));
        }
        vm.warp(block.timestamp + config.commitWindow() + 1);
        court.closeCommit(id);

        for (uint256 i = 0; i < panel.length; i++) {
            if (panel[i] == silent) continue;
            vm.prank(panel[i]);
            court.revealVote(id, DisputeCourt.Ruling.Customer100, bytes32(uint256(i + 1)));
        }
        vm.warp(block.timestamp + config.revealWindow() + 1);
        court.closeReveal(id);

        for (uint256 i = 0; i < panel.length; i++) {
            if (panel[i] == silent) continue;
            assertTrue(referral.qualified(panel[i]), "a juror who served qualifies");
        }
        assertFalse(referral.qualified(silent), "and one who stayed silent does not");
    }

    /// @dev A juror who has already qualified must not be able to stall a panel.
    function test_ARepeatJurorDoesNotStallThePanelSweep() public {
        _addJurors(5);

        uint256 first = _openAndSeat();
        _runToRuling(first);

        uint256 second = _openAndSeat();
        _runToRuling(second);

        assertEq(uint8(court.disputeOf(second).phase), uint8(DisputeCourt.Phase.Ruled), "the second round still closed");
    }

    /// @dev Drives a seated dispute through a unanimous commit and reveal.
    function _runToRuling(uint256 id) internal {
        address[] memory panel = court.panelOf(id);
        for (uint256 i = 0; i < panel.length; i++) {
            _commit(id, panel[i], DisputeCourt.Ruling.Customer100, bytes32(uint256(i + 1)));
        }
        vm.warp(block.timestamp + config.commitWindow() + 1);
        court.closeCommit(id);
        for (uint256 i = 0; i < panel.length; i++) {
            vm.prank(panel[i]);
            court.revealVote(id, DisputeCourt.Ruling.Customer100, bytes32(uint256(i + 1)));
        }
        vm.warp(block.timestamp + config.revealWindow() + 1);
        court.closeReveal(id);
    }

    // ---------------------------------------------------- sec. 30 voting

    function test_CommitRevealProducesARuling() public {
        _addJurors(5);
        uint256 id = _openAndSeat();
        address[] memory panel = court.panelOf(id);

        for (uint256 i = 0; i < panel.length; i++) {
            _commit(id, panel[i], DisputeCourt.Ruling.Customer100, bytes32(uint256(i + 1)));
        }

        vm.warp(block.timestamp + config.commitWindow() + 1);
        court.closeCommit(id);

        for (uint256 i = 0; i < panel.length; i++) {
            vm.prank(panel[i]);
            court.revealVote(id, DisputeCourt.Ruling.Customer100, bytes32(uint256(i + 1)));
        }

        vm.warp(block.timestamp + config.revealWindow() + 1);
        court.closeReveal(id);

        DisputeCourt.Dispute memory d = court.disputeOf(id);
        assertEq(uint8(d.phase), uint8(DisputeCourt.Phase.Ruled));
        assertEq(uint8(d.ruling), uint8(DisputeCourt.Ruling.Customer100));
    }

    /// @dev A commitment is bound to its dispute, round and juror (sec. 30).
    function test_AnotherJurorsCommitmentCannotBeReplayed() public {
        _addJurors(5);
        uint256 id = _openAndSeat();
        address[] memory panel = court.panelOf(id);

        bytes32 salt = bytes32(uint256(7));
        bytes32 theirs = court.hashVote(id, 1, panel[0], DisputeCourt.Ruling.Customer100, salt);
        vm.prank(panel[1]);
        court.commitVote(id, theirs);

        vm.warp(block.timestamp + config.commitWindow() + 1);
        court.closeCommit(id);

        vm.prank(panel[1]);
        vm.expectRevert();
        court.revealVote(id, DisputeCourt.Ruling.Customer100, salt);
    }

    function test_OnlySeatedJurorsMayVote() public {
        _addJurors(5);
        uint256 id = _openAndSeat();

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(DisputeCourt.NotSeated.selector, outsider));
        court.commitVote(id, keccak256("x"));
    }

    /// @dev sec. 30: the outcomes are bounded and `None` is not one of them.
    function test_RulingNoneCannotBeRevealed() public {
        _addJurors(5);
        uint256 id = _openAndSeat();
        address[] memory panel = court.panelOf(id);

        _commit(id, panel[0], DisputeCourt.Ruling.None, bytes32(uint256(1)));
        vm.warp(block.timestamp + config.commitWindow() + 1);
        court.closeCommit(id);

        vm.prank(panel[0]);
        vm.expectRevert(abi.encodeWithSelector(DisputeCourt.RulingNotAllowed.selector, DisputeCourt.Ruling.None));
        court.revealVote(id, DisputeCourt.Ruling.None, bytes32(uint256(1)));
    }

    function test_MajorityWins() public {
        _addJurors(5);
        uint256 id = _openAndSeat();
        address[] memory panel = court.panelOf(id);

        _commit(id, panel[0], DisputeCourt.Ruling.Courier100, bytes32(uint256(1)));
        _commit(id, panel[1], DisputeCourt.Ruling.Courier100, bytes32(uint256(2)));
        _commit(id, panel[2], DisputeCourt.Ruling.Customer100, bytes32(uint256(3)));

        vm.warp(block.timestamp + config.commitWindow() + 1);
        court.closeCommit(id);

        vm.prank(panel[0]);
        court.revealVote(id, DisputeCourt.Ruling.Courier100, bytes32(uint256(1)));
        vm.prank(panel[1]);
        court.revealVote(id, DisputeCourt.Ruling.Courier100, bytes32(uint256(2)));
        vm.prank(panel[2]);
        court.revealVote(id, DisputeCourt.Ruling.Customer100, bytes32(uint256(3)));

        vm.warp(block.timestamp + config.revealWindow() + 1);
        court.closeReveal(id);

        assertEq(uint8(court.disputeOf(id).ruling), uint8(DisputeCourt.Ruling.Courier100));
    }

    // ------------------------------------------- invariant sec. 33-14

    /**
     * @dev Invariant sec. 33-14. Everyone reveals, so nothing is owed to the
     *      non-reveal path; the juror who voted with the losing side keeps every
     *      wei of their stake and gets their lock back.
     *
     *      Split from the silence test on purpose: a three-seat panel cannot show
     *      both a revealed dissenter and a silent juror at once without the vote
     *      ending in a tie, and a test that has to tie to make its point is
     *      testing the tie rather than the rule.
     */
    function test_RevealedMinorityKeepsItsStake() public {
        _addJurors(5);
        uint256 id = _openAndSeat();
        address[] memory panel = court.panelOf(id);

        _commit(id, panel[0], DisputeCourt.Ruling.Courier100, bytes32(uint256(1)));
        _commit(id, panel[1], DisputeCourt.Ruling.Customer100, bytes32(uint256(2)));
        _commit(id, panel[2], DisputeCourt.Ruling.Courier100, bytes32(uint256(3)));

        vm.warp(block.timestamp + config.commitWindow() + 1);
        court.closeCommit(id);

        vm.prank(panel[0]);
        court.revealVote(id, DisputeCourt.Ruling.Courier100, bytes32(uint256(1)));
        vm.prank(panel[1]);
        court.revealVote(id, DisputeCourt.Ruling.Customer100, bytes32(uint256(2)));
        vm.prank(panel[2]);
        court.revealVote(id, DisputeCourt.Ruling.Courier100, bytes32(uint256(3)));

        uint256 dissenterBefore = pool.jurorOf(panel[1]).stake;

        vm.warp(block.timestamp + config.revealWindow() + 1);
        court.closeReveal(id);

        assertEq(uint8(court.disputeOf(id).ruling), uint8(DisputeCourt.Ruling.Courier100), "majority ruled");
        assertEq(pool.jurorOf(panel[1]).stake, dissenterBefore, "the dissenter lost nothing");
        assertEq(pool.jurorOf(panel[1]).locked, 0, "and their lock came back");
    }

    /// @dev The one path that does cost a juror: committing and then going quiet.
    function test_SilenceIsSlashed() public {
        _addJurors(5);
        uint256 id = _openAndSeat();
        address[] memory panel = court.panelOf(id);

        _commit(id, panel[0], DisputeCourt.Ruling.Courier100, bytes32(uint256(1)));
        _commit(id, panel[1], DisputeCourt.Ruling.Courier100, bytes32(uint256(2)));
        _commit(id, panel[2], DisputeCourt.Ruling.Customer100, bytes32(uint256(3)));

        vm.warp(block.timestamp + config.commitWindow() + 1);
        court.closeCommit(id);

        vm.prank(panel[0]);
        court.revealVote(id, DisputeCourt.Ruling.Courier100, bytes32(uint256(1)));
        vm.prank(panel[1]);
        court.revealVote(id, DisputeCourt.Ruling.Courier100, bytes32(uint256(2)));
        // panel[2] committed and says nothing.

        uint256 silentBefore = pool.jurorOf(panel[2]).stake;
        uint256 revealerBefore = pool.jurorOf(panel[0]).stake;

        vm.warp(block.timestamp + config.revealWindow() + 1);
        court.closeReveal(id);

        assertEq(uint8(court.disputeOf(id).ruling), uint8(DisputeCourt.Ruling.Courier100));
        assertEq(pool.jurorOf(panel[2]).stake, silentBefore - SLASH, "silence cost the slash");
        assertEq(pool.jurorOf(panel[0]).stake, revealerBefore, "and cost the others nothing");
        assertEq(pool.jurorOf(panel[2]).locked, 0, "the silent juror's lock is still released");
    }

    /// @dev Nobody revealing leaves no ruling to reach, so none is invented.
    function test_NoRevealsFailsRatherThanInventingARuling() public {
        _addJurors(5);
        uint256 id = _openAndSeat();
        address[] memory panel = court.panelOf(id);

        for (uint256 i = 0; i < panel.length; i++) {
            _commit(id, panel[i], DisputeCourt.Ruling.Customer100, bytes32(uint256(i + 1)));
        }
        vm.warp(block.timestamp + config.commitWindow() + 1);
        court.closeCommit(id);
        vm.warp(block.timestamp + config.revealWindow() + 1);
        court.closeReveal(id);

        DisputeCourt.Dispute memory d = court.disputeOf(id);
        assertEq(uint8(d.phase), uint8(DisputeCourt.Phase.Failed));
        assertEq(uint8(d.ruling), uint8(DisputeCourt.Ruling.None));
    }

    /// @dev A tie is a panel that could not decide, which sec. 30 calls Refuse.
    function test_TieResolvesToRefuse() public {
        _addJurors(5);
        uint256 id = _openAndSeat();
        address[] memory panel = court.panelOf(id);

        _commit(id, panel[0], DisputeCourt.Ruling.Courier100, bytes32(uint256(1)));
        _commit(id, panel[1], DisputeCourt.Ruling.Customer100, bytes32(uint256(2)));

        vm.warp(block.timestamp + config.commitWindow() + 1);
        court.closeCommit(id);
        vm.prank(panel[0]);
        court.revealVote(id, DisputeCourt.Ruling.Courier100, bytes32(uint256(1)));
        vm.prank(panel[1]);
        court.revealVote(id, DisputeCourt.Ruling.Customer100, bytes32(uint256(2)));

        vm.warp(block.timestamp + config.revealWindow() + 1);
        court.closeReveal(id);

        assertEq(uint8(court.disputeOf(id).ruling), uint8(DisputeCourt.Ruling.Refuse));
    }

    // ------------------------------------------------- provider outage

    /// @dev sec. 29: a silent provider costs time, not a frozen case.
    function test_SilentProviderLetsTheDrawBeAbandoned() public {
        _addJurors(4);
        uint256 id = _open();
        vm.warp(block.timestamp + config.evidenceWindow() + 1);
        uint256 drawFee = rng.fee();
        vm.prank(customer);
        court.requestDraw{value: drawFee}(id);

        vm.warp(block.timestamp + config.drawWindow() + 1);
        court.abandonDraw(id);

        assertEq(uint8(court.disputeOf(id).phase), uint8(DisputeCourt.Phase.Failed));
    }

    function test_DrawCannotBeAbandonedOnceRandomnessArrives() public {
        _addJurors(4);
        uint256 id = _open();
        vm.warp(block.timestamp + config.evidenceWindow() + 1);
        uint256 drawFee = rng.fee();
        vm.prank(customer);
        court.requestDraw{value: drawFee}(id);
        rng.deliver(court.disputeOf(id).drawRequestId, keccak256("r"));

        vm.warp(block.timestamp + config.drawWindow() + 1);
        vm.expectRevert();
        court.abandonDraw(id);
    }

    function test_PanelCannotBeSeatedBeforeRandomnessArrives() public {
        _addJurors(4);
        uint256 id = _open();
        vm.warp(block.timestamp + config.evidenceWindow() + 1);
        uint256 drawFee = rng.fee();
        vm.prank(customer);
        court.requestDraw{value: drawFee}(id);

        vm.expectRevert();
        court.seatPanel(id);
    }

    // ----------------------------------------------------------------- fuzz

    /// @dev Whatever the panel votes, the outcome is one of the six.
    function testFuzz_RulingIsAlwaysOneOfTheSix(uint8 a, uint8 b, uint8 c) public {
        _addJurors(5);
        uint256 id = _openAndSeat();
        address[] memory panel = court.panelOf(id);

        uint8 lo = uint8(DisputeCourt.Ruling.Customer100);
        uint8 hi = uint8(DisputeCourt.Ruling.Refuse);
        DisputeCourt.Ruling[3] memory votes = [
            DisputeCourt.Ruling(bound(a, lo, hi)),
            DisputeCourt.Ruling(bound(b, lo, hi)),
            DisputeCourt.Ruling(bound(c, lo, hi))
        ];

        for (uint256 i = 0; i < 3; i++) {
            _commit(id, panel[i], votes[i], bytes32(uint256(i + 1)));
        }
        vm.warp(block.timestamp + config.commitWindow() + 1);
        court.closeCommit(id);
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(panel[i]);
            court.revealVote(id, votes[i], bytes32(uint256(i + 1)));
        }
        vm.warp(block.timestamp + config.revealWindow() + 1);
        court.closeReveal(id);

        uint8 ruled = uint8(court.disputeOf(id).ruling);
        assertGe(ruled, lo, "never below the allowed range");
        assertLe(ruled, hi, "never above it");
    }

    /// @dev Revealing a different ruling than was committed is refused.
    function testFuzz_RevealMustMatchTheCommitment(uint8 committedTo, uint8 revealedAs) public {
        uint8 lo = uint8(DisputeCourt.Ruling.Customer100);
        uint8 hi = uint8(DisputeCourt.Ruling.Refuse);
        committedTo = uint8(bound(committedTo, lo, hi));
        revealedAs = uint8(bound(revealedAs, lo, hi));
        vm.assume(committedTo != revealedAs);

        _addJurors(5);
        uint256 id = _openAndSeat();
        address[] memory panel = court.panelOf(id);

        _commit(id, panel[0], DisputeCourt.Ruling(committedTo), bytes32(uint256(9)));
        vm.warp(block.timestamp + config.commitWindow() + 1);
        court.closeCommit(id);

        vm.prank(panel[0]);
        vm.expectRevert();
        court.revealVote(id, DisputeCourt.Ruling(revealedAs), bytes32(uint256(9)));
    }

    // --------------------------------------------- sec. 28: what a round costs

    /// @dev Signs a committee decision with the EOA standing in for the Safe.
    function _committeeSig(FallbackCommittee.Decision memory decision) internal view returns (bytes memory) {
        FallbackCommittee.Decision[1] memory holder = [decision];
        bytes32 digest = committee.hashDecision(holder[0]);
        (uint8 v, bytes32 r, bytes32 sg) = vm.sign(SAFE_KEY, digest);
        return abi.encodePacked(r, sg, v);
    }

    function _decision(uint256 disputeId, uint8 round, DisputeCourt.Ruling ruling)
        internal
        view
        returns (FallbackCommittee.Decision memory)
    {
        return FallbackCommittee.Decision({
            disputeId: disputeId, round: round, ruling: uint8(ruling), expiresAt: uint64(block.timestamp + 1 days)
        });
    }

    /// @dev Drives a seated dispute to a ruling, everyone voting `ruling`.
    function _rule(uint256 id, DisputeCourt.Ruling ruling) internal {
        address[] memory panel = court.panelOf(id);
        for (uint256 i = 0; i < panel.length; i++) {
            _commit(id, panel[i], ruling, bytes32(uint256(i + 1)));
        }
        vm.warp(block.timestamp + config.commitWindow() + 1);
        court.closeCommit(id);
        for (uint256 i = 0; i < panel.length; i++) {
            vm.prank(panel[i]);
            court.revealVote(id, ruling, bytes32(uint256(i + 1)));
        }
        vm.warp(block.timestamp + config.revealWindow() + 1);
        court.closeReveal(id);
    }

    /// @dev Requests and seats the panel for whatever round the dispute is on.
    function _seatCurrentRound(uint256 id) internal {
        vm.warp(block.timestamp + config.evidenceWindow() + 1);
        uint256 drawFee = rng.fee();
        vm.prank(customer);
        court.requestDraw{value: drawFee}(id);
        rng.deliver(court.disputeOf(id).drawRequestId, keccak256(abi.encode("r", court.disputeOf(id).round)));
        court.seatPanel(id);
    }

    function test_OpeningChargesTheFirstRoundScheduleAndRefundsTheRest() public {
        uint256 deliveryId = _disputableDelivery();
        uint256 cost = _roundCost(1);
        uint256 before = customer.balance;

        vm.prank(customer);
        uint256 id = court.open{value: cost + 3 ether}(deliveryId);

        assertEq(customer.balance, before - cost, "overpayment is not a donation");
        assertEq(court.totalOwed(), cost, "fee and bond are both owed to someone");
        assertEq(court.bondOf(id, 1), config.disputeBond(1));
        assertEq(court.bondPayerOf(id, 1), customer);
    }

    function test_UnderpayingTheScheduleIsRefused() public {
        uint256 deliveryId = _disputableDelivery();
        uint256 cost = _roundCost(1);

        vm.expectRevert(abi.encodeWithSelector(DisputeCourt.PaymentTooLow.selector, cost, cost - 1));
        vm.prank(customer);
        court.open{value: cost - 1}(deliveryId);
    }

    /// @dev sec. 26: a dispute is between the two parties to a delivery.
    function test_OnlyAPartyMayOpenADispute() public {
        uint256 deliveryId = _disputableDelivery();
        uint256 cost = _roundCost(1);
        vm.deal(outsider, 100 ether);

        vm.expectRevert(abi.encodeWithSelector(DisputeCourt.NotAParty.selector, outsider));
        vm.prank(outsider);
        court.open{value: cost}(deliveryId);
    }

    /**
     * @dev The same rule as opening, and it was missing: an appeal escalates a
     *      case the appellant is not in. Caught by a mutation that removed the
     *      check and broke nothing.
     */
    function test_OnlyAPartyMayAppeal() public {
        _addJurors(12);
        uint256 id = _openAndSeat();
        _rule(id, DisputeCourt.Ruling.Customer100);

        uint256 cost2 = _roundCost(2);
        vm.deal(outsider, 100 ether);

        vm.expectRevert(abi.encodeWithSelector(DisputeCourt.NotAParty.selector, outsider));
        vm.prank(outsider);
        court.appeal{value: cost2}(id);

        assertEq(court.disputeOf(id).round, 1, "and the round did not move");
    }

    function test_ADeliveryCanOnlyBeDisputedOnce() public {
        uint256 deliveryId = _disputableDelivery();
        uint256 cost = _roundCost(1);
        vm.prank(customer);
        uint256 id = court.open{value: cost}(deliveryId);

        vm.expectRevert(abi.encodeWithSelector(DisputeCourt.DisputeAlreadyOpen.selector, deliveryId, id));
        vm.prank(customer);
        court.open{value: cost}(deliveryId);
    }

    /**
     * @dev sec. 26 is explicit that a deterministic situation must not become a
     *      jury case. A delivery still taking bids has nothing for a jury to
     *      interpret, and the hub is the one that says so.
     */
    function test_ADeliveryWithNothingToJudgeCannotBeDisputed() public {
        CoverageQuote.Quote memory q = buildQuote(config, customer, 1, DECLARED_VALUE);
        bytes memory qsig = signQuote(hub, q);
        vm.prank(customer);
        uint256 deliveryId = hub.createDelivery(q, qsig);

        uint256 cost = _roundCost(1);
        vm.expectRevert(
            abi.encodeWithSelector(DeliveryHub.NotDisputable.selector, deliveryId, DeliveryHub.State.Bidding)
        );
        vm.prank(customer);
        court.open{value: cost}(deliveryId);
    }

    // ------------------------------------------------- sec. 28: the escalation

    function test_AppealsEscalateThreeThenFiveThenSeven() public {
        _addJurors(12);
        uint256 id = _openAndSeat();

        assertEq(court.panelSize(id), config.juryFirstSize(), "first panel is three");
        _rule(id, DisputeCourt.Ruling.Customer100);

        uint256 cost2 = _roundCost(2);
        vm.prank(courier);
        court.appeal{value: cost2}(id);
        _seatCurrentRound(id);
        assertEq(court.disputeOf(id).round, 2);
        assertEq(court.panelSize(id), config.juryAppeal1Size(), "appeal one is five");
        _rule(id, DisputeCourt.Ruling.Customer100);

        uint256 cost3 = _roundCost(3);
        vm.prank(courier);
        court.appeal{value: cost3}(id);
        _seatCurrentRound(id);
        assertEq(court.disputeOf(id).round, 3);
        assertEq(court.panelSize(id), config.juryAppeal2Size(), "appeal two is seven");
    }

    /// @dev sec. 28's schedule has three rows and no fourth.
    function test_ThereIsNoFourthRound() public {
        _addJurors(12);
        uint256 id = _openAndSeat();
        _rule(id, DisputeCourt.Ruling.Customer100);

        uint256 cost2 = _roundCost(2);
        vm.prank(courier);
        court.appeal{value: cost2}(id);
        _seatCurrentRound(id);
        _rule(id, DisputeCourt.Ruling.Customer100);

        uint256 cost3 = _roundCost(3);
        vm.prank(courier);
        court.appeal{value: cost3}(id);
        _seatCurrentRound(id);
        _rule(id, DisputeCourt.Ruling.Customer100);

        vm.expectRevert(abi.encodeWithSelector(DisputeCourt.NoFurtherAppeal.selector, uint8(3)));
        vm.prank(courier);
        court.appeal{value: cost3}(id);
    }

    function test_AnAppealAfterTheWindowClosesIsRefused() public {
        _addJurors(5);
        uint256 id = _openAndSeat();
        _rule(id, DisputeCourt.Ruling.Customer100);

        uint64 closesAt = court.disputeOf(id).phaseDeadline;
        vm.warp(closesAt + 1);

        uint256 cost2 = _roundCost(2);
        vm.expectRevert(abi.encodeWithSelector(DisputeCourt.AppealWindowClosed.selector, closesAt));
        vm.prank(courier);
        court.appeal{value: cost2}(id);
    }

    /// @dev The loser always gets their chance to escalate before money moves.
    function test_FinalisingBeforeTheAppealWindowClosesIsRefused() public {
        _addJurors(5);
        uint256 id = _openAndSeat();
        _rule(id, DisputeCourt.Ruling.Customer100);

        uint64 closesAt = court.disputeOf(id).phaseDeadline;
        vm.expectRevert(abi.encodeWithSelector(DisputeCourt.AppealWindowOpen.selector, closesAt));
        court.finalise(id);
    }

    // --------------------------------------------- sec. 30: ruling into money

    function test_ARulingSettlesTheEscrowAndOnlyOnce() public {
        _addJurors(5);
        uint256 id = _openAndSeat();
        uint256 deliveryId = court.disputeOf(id).deliveryId;
        uint256 escrow = hub.customerFundingAmount(deliveryId);

        _rule(id, DisputeCourt.Ruling.Customer100);
        vm.warp(block.timestamp + config.appealWindow() + 1);
        court.finalise(id);

        assertEq(uint8(hub.deliveryOf(deliveryId).state), uint8(DeliveryHub.State.Resolved));
        assertEq(vault.claimableOf(customer), escrow, "the whole escrow went to the customer");
        assertEq(vault.claimableOf(courier), 0);
        assertEq(registry.courierOf(courier).reserved, 0, "and the coverage was released");

        vm.expectRevert(
            abi.encodeWithSelector(
                DisputeCourt.WrongPhase.selector, id, DisputeCourt.Phase.Settled, DisputeCourt.Phase.Ruled
            )
        );
        court.finalise(id);
    }

    /// @dev Whichever of the six the panel picks, the escrow is split, never lost.
    function test_EveryRulingSplitsTheWholeEscrow() public {
        for (uint8 code = 1; code <= 6; code++) {
            _checkSplit(DisputeCourt.Ruling(code));
        }
    }

    function _checkSplit(DisputeCourt.Ruling ruling) internal {
        uint256 snapshot = vm.snapshotState();
        _addJurors(5);
        uint256 id = _openAndSeat();
        uint256 deliveryId = court.disputeOf(id).deliveryId;
        uint256 escrow = hub.customerFundingAmount(deliveryId);

        _rule(id, ruling);
        vm.warp(block.timestamp + config.appealWindow() + 1);
        court.finalise(id);

        assertEq(
            vault.claimableOf(customer) + vault.claimableOf(courier),
            escrow,
            "a ruling apportions the escrow; it never creates or destroys any"
        );
        assertEq(vault.claimableOf(treasury), 0, "and a disputed delivery pays no protocol fee");
        vm.revertToState(snapshot);
    }

    /// @dev `Refuse` is a panel declining to decide, not a courier win.
    function test_RefusingToRuleReturnsTheEscrow() public {
        _addJurors(5);
        uint256 id = _openAndSeat();
        uint256 deliveryId = court.disputeOf(id).deliveryId;
        uint256 escrow = hub.customerFundingAmount(deliveryId);

        _rule(id, DisputeCourt.Ruling.Refuse);
        vm.warp(block.timestamp + config.appealWindow() + 1);
        court.finalise(id);

        assertEq(vault.claimableOf(customer), escrow);
        assertEq(vault.claimableOf(courier), 0);
    }

    // --------------------------------------------------- sec. 28: the bonds

    function test_TheParticipationBondComesBackAndTheFeeGoesToTheTreasury() public {
        _addJurors(5);
        uint256 id = _openAndSeat();

        _rule(id, DisputeCourt.Ruling.Customer100);
        vm.warp(block.timestamp + config.appealWindow() + 1);
        court.finalise(id);

        assertEq(court.claimable(customer), config.disputeBond(1), "taking part is not a wager");
        assertEq(court.claimable(treasury), config.arbitrationFee(1), "the fee is earned");
    }

    /// @dev An appeal that changes the answer was worth hearing; its bond returns.
    function test_ASuccessfulAppealGetsItsBondBack() public {
        _addJurors(12);
        uint256 id = _openAndSeat();
        _rule(id, DisputeCourt.Ruling.Customer100);

        uint256 cost2 = _roundCost(2);
        vm.prank(courier);
        court.appeal{value: cost2}(id);
        _seatCurrentRound(id);
        _rule(id, DisputeCourt.Ruling.Courier100);

        vm.warp(block.timestamp + config.appealWindow() + 1);
        court.finalise(id);

        assertEq(court.claimable(courier), config.disputeBond(2), "the larger panel disagreed");
    }

    /// @dev One that does not is paying to delay, and the bond is forfeited.
    function test_AFailedAppealForfeitsItsBond() public {
        _addJurors(12);
        uint256 id = _openAndSeat();
        _rule(id, DisputeCourt.Ruling.Customer100);

        uint256 cost2 = _roundCost(2);
        vm.prank(courier);
        court.appeal{value: cost2}(id);
        _seatCurrentRound(id);
        _rule(id, DisputeCourt.Ruling.Customer100);

        vm.warp(block.timestamp + config.appealWindow() + 1);
        court.finalise(id);

        assertEq(court.claimable(courier), 0, "the same answer twice is not a win");
        assertEq(
            court.claimable(treasury),
            uint256(config.arbitrationFee(1)) + config.arbitrationFee(2) + config.disputeBond(2),
            "the forfeited bond joins the fees"
        );
    }

    /**
     * @dev The court holds bonds and fees belonging to several people at once.
     *      `solvent` is the guard that stops it paying one of them out of
     *      another's money, and no ordinary path can reach it — every function
     *      that takes value counts it, and every function that pays it out
     *      discounts it. So the balance is corrupted here deliberately, which is
     *      the only honest way to prove a safety net catches anything.
     */
    function test_ACourtThatCannotCoverWhatItOwesRefusesToAct() public {
        _addJurors(5);
        uint256 id = _openAndSeat();
        _rule(id, DisputeCourt.Ruling.Customer100);
        vm.warp(block.timestamp + config.appealWindow() + 1);

        uint256 owed = court.totalOwed();
        assertGt(owed, 0, "the court is holding something worth protecting");
        vm.deal(address(court), owed - 1);

        vm.expectRevert(abi.encodeWithSelector(DisputeCourt.Insolvent.selector, owed, owed - 1));
        court.finalise(id);
    }

    function test_ClaimPaysExactlyOnce() public {
        _addJurors(5);
        uint256 id = _openAndSeat();
        _rule(id, DisputeCourt.Ruling.Customer100);
        vm.warp(block.timestamp + config.appealWindow() + 1);
        court.finalise(id);

        uint256 owed = court.claimable(customer);
        uint256 before = customer.balance;
        vm.prank(customer);
        court.claim();

        assertEq(customer.balance, before + owed);
        assertEq(court.claimable(customer), 0);

        vm.expectRevert(abi.encodeWithSelector(DisputeCourt.NothingToClaim.selector, customer));
        vm.prank(customer);
        court.claim();
    }

    // ----------------------------------------------------- sec. 31: fallback

    /// @dev The committee is for a jury that produced nothing, never for one that did.
    function test_TheCommitteeCannotTouchARunningDispute() public {
        _addJurors(5);
        uint256 id = _openAndSeat();

        FallbackCommittee.Decision memory decision = _decision(id, 1, DisputeCourt.Ruling.Courier100);
        bytes memory sig = _committeeSig(decision);

        vm.expectRevert(
            abi.encodeWithSelector(
                DisputeCourt.WrongPhase.selector, id, DisputeCourt.Phase.Commit, DisputeCourt.Phase.Failed
            )
        );
        court.resolveByCommittee(id, decision, sig);
    }

    function test_TheCommitteeEndsACaseNobodyRevealed() public {
        _addJurors(5);
        uint256 id = _openAndSeat();
        uint256 deliveryId = court.disputeOf(id).deliveryId;
        uint256 escrow = hub.customerFundingAmount(deliveryId);

        vm.warp(block.timestamp + config.commitWindow() + 1);
        court.closeCommit(id);
        vm.warp(block.timestamp + config.revealWindow() + 1);
        court.closeReveal(id);
        assertEq(uint8(court.disputeOf(id).phase), uint8(DisputeCourt.Phase.Failed), "no reveals, no ruling");

        FallbackCommittee.Decision memory decision = _decision(id, 1, DisputeCourt.Ruling.Courier100);
        bytes memory sig = _committeeSig(decision);
        court.resolveByCommittee(id, decision, sig);

        assertEq(uint8(hub.deliveryOf(deliveryId).state), uint8(DeliveryHub.State.Resolved));
        assertEq(vault.claimableOf(courier), escrow, "the committee's ruling settled it");
    }

    /// @dev sec. 31's whole point: bounded codes, never a transfer.
    function test_TheCommitteeCannotSignSomethingThatIsNotARuling() public {
        uint256 id = _failedDispute();

        for (uint256 i = 0; i < 2; i++) {
            uint8 code = i == 0 ? 0 : 7;
            FallbackCommittee.Decision memory decision = FallbackCommittee.Decision({
                disputeId: id, round: 1, ruling: code, expiresAt: uint64(block.timestamp + 1 days)
            });
            bytes memory sig = _committeeSig(decision);

            vm.expectRevert(abi.encodeWithSelector(FallbackCommittee.RulingNotAllowed.selector, code));
            court.resolveByCommittee(id, decision, sig);
        }
    }

    function test_ACommitteeDecisionIsBoundToItsDisputeAndRound() public {
        uint256 id = _failedDispute();

        FallbackCommittee.Decision memory wrongDispute = _decision(id + 1, 1, DisputeCourt.Ruling.Courier100);
        bytes memory sig1 = _committeeSig(wrongDispute);
        vm.expectRevert(abi.encodeWithSelector(FallbackCommittee.WrongDispute.selector, id, id + 1));
        court.resolveByCommittee(id, wrongDispute, sig1);

        FallbackCommittee.Decision memory wrongRound = _decision(id, 2, DisputeCourt.Ruling.Courier100);
        bytes memory sig2 = _committeeSig(wrongRound);
        vm.expectRevert(abi.encodeWithSelector(FallbackCommittee.WrongRound.selector, uint8(1), uint8(2)));
        court.resolveByCommittee(id, wrongRound, sig2);
    }

    function test_AnExpiredCommitteeDecisionIsRefused() public {
        uint256 id = _failedDispute();

        FallbackCommittee.Decision memory decision = _decision(id, 1, DisputeCourt.Ruling.Courier100);
        bytes memory sig = _committeeSig(decision);
        vm.warp(decision.expiresAt + 1);

        vm.expectRevert(abi.encodeWithSelector(FallbackCommittee.DecisionExpired.selector, decision.expiresAt));
        court.resolveByCommittee(id, decision, sig);
    }

    function test_SomebodyElsesSignatureIsNotTheCommittees() public {
        uint256 id = _failedDispute();

        FallbackCommittee.Decision memory decision = _decision(id, 1, DisputeCourt.Ruling.Courier100);
        bytes32 digest = committee.hashDecision(decision);
        (uint8 v, bytes32 r, bytes32 sg) = vm.sign(uint256(0xBADBAD), digest);
        bytes memory forged = abi.encodePacked(r, sg, v);

        vm.expectRevert(abi.encodeWithSelector(FallbackCommittee.DecisionSignatureInvalid.selector, digest));
        court.resolveByCommittee(id, decision, forged);
    }

    /// @dev The real shape of sec. 31: a Safe, answering through ERC-1271.
    function test_AContractWalletSignatureIsAccepted() public {
        StubSafe realSafe = new StubSafe();
        vm.prank(signerAdmin);
        committee.setSafe(address(realSafe));

        uint256 id = _failedDispute();
        FallbackCommittee.Decision memory decision = _decision(id, 1, DisputeCourt.Ruling.Split50);
        realSafe.approve(committee.hashDecision(decision));

        court.resolveByCommittee(id, decision, hex"");
        assertEq(uint8(court.disputeOf(id).phase), uint8(DisputeCourt.Phase.Settled));
    }

    /// @dev A dispute that reached `Failed` with no committee answer yet.
    function _failedDispute() internal returns (uint256 id) {
        _addJurors(5);
        id = _openAndSeat();
        vm.warp(block.timestamp + config.commitWindow() + 1);
        court.closeCommit(id);
        vm.warp(block.timestamp + config.revealWindow() + 1);
        court.closeReveal(id);
    }

    // ------------------------------------------ no dispute can freeze funds

    /**
     * @dev The acceptance criterion, exercised end to end: the court goes
     *      completely silent, and the escrow still reaches someone. The hub's
     *      long stop settles the delivery, and `abandon` returns everything the
     *      court was holding, because nothing was ever adjudicated.
     */
    function test_ASilentCourtCannotFreezeAnybodysMoney() public {
        uint256 deliveryId = _disputableDelivery();
        uint256 escrow = hub.customerFundingAmount(deliveryId);
        uint256 cost = _roundCost(1);
        vm.prank(customer);
        uint256 id = court.open{value: cost}(deliveryId);

        // Nothing happens. Ever.
        vm.warp(block.timestamp + config.disputeWindow() + 1);
        hub.poke(deliveryId);

        assertEq(uint8(hub.deliveryOf(deliveryId).state), uint8(DeliveryHub.State.Resolved));
        assertEq(vault.claimableOf(customer), escrow, "the escrow came back");
        assertEq(registry.courierOf(courier).reserved, 0, "and the coverage was released unslashed");

        court.abandon(id);
        assertEq(uint8(court.disputeOf(id).phase), uint8(DisputeCourt.Phase.Abandoned));
        assertEq(court.claimable(customer), cost, "fee and bond both come back; nothing was tried");
    }

    /// @dev And the long stop cannot fire early, under a jury still working.
    function test_TheLongStopCannotSettleUnderALiveJury() public {
        _addJurors(5);
        uint256 id = _openAndSeat();
        uint256 deliveryId = court.disputeOf(id).deliveryId;

        uint64 longStop = hub.deliveryOf(deliveryId).stateDeadline;
        vm.warp(block.timestamp + 1 days);
        vm.expectRevert(abi.encodeWithSelector(DeliveryHub.DeadlineNotReached.selector, longStop));
        hub.poke(deliveryId);

        assertEq(uint8(hub.deliveryOf(deliveryId).state), uint8(DeliveryHub.State.Disputed));
    }

    /// @dev A dispute the hub has not settled cannot be abandoned out from under it.
    function test_ALiveDisputeCannotBeAbandoned() public {
        uint256 deliveryId = _disputableDelivery();
        uint256 cost = _roundCost(1);
        vm.prank(customer);
        uint256 id = court.open{value: cost}(deliveryId);

        vm.expectRevert(abi.encodeWithSelector(DisputeCourt.DeliveryStillDisputed.selector, deliveryId));
        court.abandon(id);
    }
}
