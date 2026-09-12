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
contract DisputeCourtTest is Test {
    ProtocolAccessManager internal manager;
    ProtocolConfig internal config;
    JurorPool internal pool;
    Referral internal referral;
    StubRandomness internal rng;
    DisputeCourt internal court;

    address internal admin = address(0xA11CE);
    address internal treasury = address(0x7EA5);
    address internal configAdmin = address(0xC0F1);
    address internal customer = address(0xC057);
    address internal outsider = address(0xBAD);

    uint256 internal MIN;
    uint256 internal SLASH;

    address[] internal jurorList;

    function setUp() public {
        manager = new ProtocolAccessManager(3 days, admin);
        config = new ProtocolConfig(manager, 2 days, BaselineParams.baseline(), treasury, address(0x1), address(0x2));
        pool = new JurorPool(manager, config);
        rng = new StubRandomness();
        referral = new Referral(manager);
        court = new DisputeCourt(manager, config, pool, IRandomnessAdapter(address(rng)), referral);

        bytes32 role = manager.DISPUTE_COURT_ROLE();
        bytes32 reporter = manager.REFERRAL_REPORTER_ROLE();
        bytes32 configRole = manager.CONFIG_ADMIN_ROLE();
        vm.startPrank(admin);
        manager.grantRole(role, address(court));
        manager.grantRole(reporter, address(court));
        manager.grantRole(configRole, configAdmin);
        vm.stopPrank();

        MIN = config.minJurorStake();
        SLASH = config.nonRevealSlash();

        vm.deal(customer, 100 ether);
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

    function _openAndSeat() internal returns (uint256 id) {
        vm.prank(customer);
        id = court.open(1);

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
        vm.prank(customer);
        uint256 id = court.open(42);

        DisputeCourt.Dispute memory d = court.disputeOf(id);
        assertEq(uint8(d.phase), uint8(DisputeCourt.Phase.Evidence));
        assertEq(d.deliveryId, 42);
        assertEq(d.round, 1);
    }

    /// @dev sec. 34: only a commitment reaches the chain, never the material.
    function test_EvidenceIsOnlyAHash() public {
        vm.prank(customer);
        uint256 id = court.open(1);

        bytes32 commitment = keccak256("photo of the doorstep");
        vm.prank(customer);
        court.submitEvidence(id, commitment);
        assertEq(court.evidenceOf(id, customer), commitment);
    }

    function test_EvidenceClosesOnTime() public {
        vm.prank(customer);
        uint256 id = court.open(1);
        vm.warp(block.timestamp + config.evidenceWindow() + 1);

        vm.prank(customer);
        vm.expectRevert();
        court.submitEvidence(id, keccak256("late"));
    }

    function test_DrawCannotStartBeforeEvidenceCloses() public {
        _addJurors(4);
        vm.prank(customer);
        uint256 id = court.open(1);

        vm.prank(customer);
        uint256 drawFee = rng.fee();
        vm.expectRevert();
        court.requestDraw{value: drawFee}(id);
    }

    /// @dev sec. 29: the fee is passed through, the surplus comes back.
    function test_DrawFeeIsPassedThroughAndExcessRefunded() public {
        _addJurors(4);
        vm.prank(customer);
        uint256 id = court.open(1);
        vm.warp(block.timestamp + config.evidenceWindow() + 1);

        uint256 before = customer.balance;
        uint256 drawFee = rng.fee();
        vm.prank(customer);
        court.requestDraw{value: drawFee + 1 ether}(id);

        assertEq(customer.balance, before - rng.fee(), "only the provider's fee left");
        assertEq(address(court).balance, 0, "and the court keeps nothing");
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
        vm.prank(customer);
        uint256 id = court.open(1);
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

        vm.prank(customer);
        uint256 id = court.open(1);
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

        vm.prank(customer);
        uint256 id = court.open(1);
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
        vm.prank(customer);
        uint256 id = court.open(1);
        vm.warp(block.timestamp + config.evidenceWindow() + 1);
        uint256 drawFee = rng.fee();

        vm.expectRevert(abi.encodeWithSelector(JurorPool.SnapshotEmpty.selector, id));
        vm.prank(customer);
        court.requestDraw{value: drawFee}(id);
    }

    function test_TooFewCandidatesFailsRatherThanRepeating() public {
        _addJurors(2);
        vm.prank(customer);
        uint256 id = court.open(1);
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
        vm.prank(customer);
        uint256 id = court.open(1);
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

        vm.prank(customer);
        uint256 id = court.open(1);
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
        vm.prank(customer);
        uint256 id = court.open(1);
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
        vm.prank(customer);
        uint256 id = court.open(1);
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
        vm.prank(customer);
        uint256 id = court.open(1);
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
}
