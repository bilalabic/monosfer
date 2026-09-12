// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {ProtocolAccessManager} from "../access/ProtocolAccessManager.sol";
import {ProtocolConfig} from "../config/ProtocolConfig.sol";
import {IRandomnessAdapter} from "../randomness/IRandomnessAdapter.sol";
import {JurorPool} from "./JurorPool.sol";
import {Referral} from "../rewards/Referral.sol";

/**
 * @title DisputeCourt
 * @notice Evidence, a random jury, and a commit/reveal vote over bounded rulings.
 * @dev Baseline refs: sec. 26 (what disputes are for), sec. 28 (lifecycle and the
 *      3/5/7 escalation), sec. 29 (randomness through an adapter), sec. 30
 *      (commit/reveal and the six outcomes), sec. 32.6, invariants sec. 33-13,
 *      sec. 33-14 and sec. 33-18.
 *
 *      ## A ruling is a choice from six, not a payment instruction
 *
 *      sec. 30 bounds the outcomes and says jurors cannot supply addresses or
 *      percentages. So a vote here is an enum, and settlement reads it. There is
 *      no field a juror could fill with a destination, and no arithmetic they can
 *      influence — the worst a captured jury can do is pick the wrong one of six
 *      answers, which is a dispute about judgement rather than a theft.
 *
 *      ## Evidence is committed, not stored
 *
 *      Only hashes go on chain. The material itself is off-chain (sec. 34), and
 *      publishing it here would put a photograph of someone's front door in
 *      permanent public storage to settle a parcel dispute.
 *
 *      ## The court reads randomness; randomness never calls the court
 *
 *      The adapter records what the provider sends and the court fetches it in a
 *      transaction of its own (sec. 29). A provider that never answers leaves the
 *      draw unfulfilled, and the draw has a deadline, so a silent provider costs
 *      time rather than freezing a case.
 *
 *      ## Only failing to reveal is punished
 *
 *      Invariant sec. 33-14: a juror who reveals a losing vote keeps their stake.
 *      The single call this contract makes into the pool's slashing path is named
 *      for the reason it exists and is reachable only from the reveal deadline,
 *      never from counting votes.
 */
contract DisputeCourt is ReentrancyGuard {
    // --------------------------------------------------------------------
    // Types
    // --------------------------------------------------------------------

    /// @notice The six outcomes sec. 30 allows. Nothing else can be voted.
    enum Ruling {
        None,
        Customer100,
        Customer75,
        Split50,
        Customer25,
        Courier100,
        Refuse
    }

    enum Phase {
        None,
        Evidence,
        AwaitingDraw,
        Commit,
        Reveal,
        Ruled,
        Failed
    }

    struct Dispute {
        uint256 deliveryId;
        address opener;
        Phase phase;
        uint8 round;
        uint64 phaseDeadline;
        uint64 drawRequestId;
        Ruling ruling;
        uint16 committed;
        uint16 revealed;
    }

    // --------------------------------------------------------------------
    // Storage
    // --------------------------------------------------------------------

    ProtocolAccessManager public immutable accessManager;
    ProtocolConfig public immutable config;
    JurorPool public immutable jurors;
    IRandomnessAdapter public immutable randomness;

    /// @notice Where a first finalised jury round is reported (sec. 25). May be zero.
    Referral public immutable referral;

    uint256 public nextDisputeId;

    mapping(uint256 => Dispute) internal _disputes;
    /// @notice Evidence commitments, by dispute and submitter.
    mapping(uint256 => mapping(address => bytes32)) public evidenceOf;
    /// @notice The seated panel for a dispute's current round.
    // A mapping has no initial value to give it; every key already reads as an
    // empty array. Slither reports the declaration anyway.
    // slither-disable-next-line uninitialized-state
    mapping(uint256 => address[]) internal _panel;
    mapping(uint256 => mapping(address => bool)) public isSeated;
    mapping(uint256 => mapping(address => bytes32)) public commitmentOf;
    mapping(uint256 => mapping(address => Ruling)) public revealedVote;
    mapping(uint256 => mapping(uint8 => uint16)) public tally;

    // --------------------------------------------------------------------
    // Events and errors
    // --------------------------------------------------------------------

    event DisputeOpened(uint256 indexed disputeId, uint256 indexed deliveryId, address indexed opener);
    event EvidenceSubmitted(uint256 indexed disputeId, address indexed submitter, bytes32 commitment);
    event DrawRequested(uint256 indexed disputeId, uint64 requestId, uint256 candidates, uint256 feePaid);
    event PanelSeated(uint256 indexed disputeId, uint8 round, address[] panel);
    event VoteCommitted(uint256 indexed disputeId, address indexed juror);
    event VoteRevealed(uint256 indexed disputeId, address indexed juror, Ruling ruling);
    event DisputeRuled(uint256 indexed disputeId, uint8 round, Ruling ruling, uint16 votes);
    event DisputeFailed(uint256 indexed disputeId, string reason);

    error ZeroAddress();
    error UnknownDispute(uint256 disputeId);
    error WrongPhase(uint256 disputeId, Phase actual, Phase expected);
    error DeadlineNotReached(uint64 deadline);
    error DeadlinePassed(uint64 deadline);
    error NotSeated(address caller);
    error AlreadyCommitted(address juror);
    error NothingCommitted(address juror);
    error AlreadyRevealed(address juror);
    error RulingNotAllowed(Ruling ruling);
    error CommitmentMismatch(bytes32 expected, bytes32 actual);
    error RandomnessNotReady(uint64 requestId);
    error FeeTooLow(uint256 required, uint256 provided);
    error PanelTooSmall(uint256 seated, uint256 wanted);
    error RefundFailed(address to, uint256 amount);

    /// @notice A juror's referral qualification could not be recorded. Never fatal.
    event ReferralReportFailed(address indexed juror, bytes data);

    // --------------------------------------------------------------------
    // Wiring
    // --------------------------------------------------------------------

    constructor(
        ProtocolAccessManager accessManager_,
        ProtocolConfig config_,
        JurorPool jurors_,
        IRandomnessAdapter randomness_,
        Referral referral_
    ) {
        if (address(accessManager_) == address(0)) revert ZeroAddress();
        if (address(config_) == address(0)) revert ZeroAddress();
        if (address(jurors_) == address(0)) revert ZeroAddress();
        if (address(randomness_) == address(0)) revert ZeroAddress();

        accessManager = accessManager_;
        config = config_;
        jurors = jurors_;
        randomness = randomness_;
        // May be zero: a deployment without a referral programme still judges
        // disputes. Everything else above is load-bearing and is checked.
        referral = referral_;
    }

    // --------------------------------------------------------------------
    // Opening and evidence
    // --------------------------------------------------------------------

    /**
     * @notice Open a dispute over a delivery.
     * @dev sec. 26: this is for facts that need interpreting. A delivery that
     *      merely timed out resolves deterministically and never arrives here —
     *      `DeliveryHub` settles those itself.
     */
    function open(uint256 deliveryId) external returns (uint256 disputeId) {
        disputeId = nextDisputeId++;
        _disputes[disputeId] = Dispute({
            deliveryId: deliveryId,
            opener: msg.sender,
            phase: Phase.Evidence,
            round: 1,
            phaseDeadline: uint64(block.timestamp) + config.evidenceWindow(),
            drawRequestId: 0,
            ruling: Ruling.None,
            committed: 0,
            revealed: 0
        });
        emit DisputeOpened(disputeId, deliveryId, msg.sender);
    }

    /**
     * @notice Commit to a piece of evidence.
     * @dev The hash only. sec. 34 keeps the material off-chain, and a commitment
     *      is enough for a juror to check that what they were shown is what was
     *      filed.
     */
    function submitEvidence(uint256 disputeId, bytes32 commitment) external {
        Dispute storage d = _requireDispute(disputeId);
        _requirePhase(disputeId, d, Phase.Evidence);
        if (block.timestamp > d.phaseDeadline) revert DeadlinePassed(d.phaseDeadline);

        evidenceOf[disputeId][msg.sender] = commitment;
        emit EvidenceSubmitted(disputeId, msg.sender, commitment);
    }

    // --------------------------------------------------------------------
    // The draw
    // --------------------------------------------------------------------

    /**
     * @notice Close evidence and ask for the randomness that picks the panel.
     * @dev The candidate set is frozen here rather than when the value arrives,
     *      which is what stops anyone joining or leaving to steer it
     *      (invariant sec. 33-18). The provider's fee is passed through (sec. 29);
     *      anything above it comes back.
     */
    function requestDraw(uint256 disputeId) external payable nonReentrant {
        Dispute storage d = _requireDispute(disputeId);
        _requirePhase(disputeId, d, Phase.Evidence);
        if (block.timestamp <= d.phaseDeadline) revert DeadlineNotReached(d.phaseDeadline);

        uint256 fee = randomness.fee();
        if (msg.value < fee) revert FeeTooLow(fee, msg.value);

        uint256 candidates = jurors.takeSnapshot(disputeId);
        uint64 requestId =
            randomness.request{value: fee}(keccak256(abi.encode(disputeId, d.round, block.timestamp, msg.sender)));

        d.drawRequestId = requestId;
        d.phase = Phase.AwaitingDraw;
        d.phaseDeadline = uint64(block.timestamp) + config.drawWindow();
        emit DrawRequested(disputeId, requestId, candidates, fee);

        uint256 excess = msg.value - fee;
        if (excess > 0) {
            (bool ok,) = msg.sender.call{value: excess}("");
            if (!ok) revert RefundFailed(msg.sender, excess);
        }
    }

    /**
     * @notice Seat the panel once the random value has arrived.
     * @dev Selection walks the frozen set from a random start, taking each
     *      candidate at most once (invariant sec. 33-13) and skipping anyone
     *      whose stake no longer covers the per-case lock.
     */
    function seatPanel(uint256 disputeId) external nonReentrant {
        Dispute storage d = _requireDispute(disputeId);
        _requirePhase(disputeId, d, Phase.AwaitingDraw);

        (bytes32 value, bool fulfilled) = randomness.randomnessOf(d.drawRequestId);
        if (!fulfilled) revert RandomnessNotReady(d.drawRequestId);

        uint256 size = jurors.snapshotSize(disputeId);
        uint256 wanted = _panelSize(d.round);
        address[] storage panel = _panel[disputeId];

        // A stride coprime with the set size visits every position exactly once,
        // so a juror cannot be drawn twice and the walk cannot cycle early.
        //
        // The `size > 1` guard is not a nicety: picking a stride out of
        // `% (size - 1)` divides by zero when exactly one candidate stood, and a
        // panel that is merely impossible to fill must fail as `PanelTooSmall`
        // below rather than as a panic. With one candidate every stride is
        // trivially coprime, so there is nothing to search for either. An empty
        // snapshot never reaches here at all -- `takeSnapshot` refuses one.
        uint256 start = uint256(value) % size;
        uint256 stride = 1;
        if (size > 1) {
            stride = (uint256(keccak256(abi.encode(value, "stride"))) % (size - 1)) + 1;
            while (_gcd(stride, size) != 1) {
                stride = stride == size - 1 ? 1 : stride + 1;
            }
        }

        uint256 cursor = start;
        for (uint256 i = 0; i < size && panel.length < wanted; i++) {
            address candidate = jurors.snapshotAt(disputeId, cursor);
            cursor = (cursor + stride) % size;

            if (isSeated[disputeId][candidate]) continue;
            if (!jurors.seat(disputeId, candidate)) continue;

            // `isSeated` is written after `jurors.seat` returns, which Slither
            // reads as cross-function reentrancy against `commitVote` and
            // `revealVote`. The callee is `JurorPool`, fixed at construction,
            // holding no untrusted code and making no call of its own; there is
            // no path from it back into this contract. Ordering the write first
            // would mean rolling it back when seating is refused, which is a
            // write after the same call by another name. The function is
            // `nonReentrant` regardless.
            // slither-disable-next-line reentrancy-no-eth
            isSeated[disputeId][candidate] = true;
            panel.push(candidate);
        }

        if (panel.length < wanted) revert PanelTooSmall(panel.length, wanted);

        d.phase = Phase.Commit;
        d.phaseDeadline = uint64(block.timestamp) + config.commitWindow();
        emit PanelSeated(disputeId, d.round, panel);
    }

    /**
     * @notice Give up on a draw the provider never answered (sec. 29).
     * @dev Failing the dispute here is deliberate: it releases the jurors and
     *      hands the delivery back to whatever the settlement layer does with an
     *      unresolved case, rather than leaving the money waiting on a call that
     *      is not coming.
     */
    function abandonDraw(uint256 disputeId) external {
        Dispute storage d = _requireDispute(disputeId);
        _requirePhase(disputeId, d, Phase.AwaitingDraw);
        if (block.timestamp <= d.phaseDeadline) revert DeadlineNotReached(d.phaseDeadline);
        if (randomness.isFulfilled(d.drawRequestId)) revert RandomnessNotReady(d.drawRequestId);

        d.phase = Phase.Failed;
        d.phaseDeadline = 0;
        emit DisputeFailed(disputeId, "randomness never arrived");
    }

    // --------------------------------------------------------------------
    // Voting (sec. 30)
    // --------------------------------------------------------------------

    /// @notice Commit to a ruling without revealing it.
    function commitVote(uint256 disputeId, bytes32 voteHash) external {
        Dispute storage d = _requireDispute(disputeId);
        _requirePhase(disputeId, d, Phase.Commit);
        if (block.timestamp > d.phaseDeadline) revert DeadlinePassed(d.phaseDeadline);
        if (!isSeated[disputeId][msg.sender]) revert NotSeated(msg.sender);
        if (commitmentOf[disputeId][msg.sender] != bytes32(0)) revert AlreadyCommitted(msg.sender);

        commitmentOf[disputeId][msg.sender] = voteHash;
        d.committed += 1;
        emit VoteCommitted(disputeId, msg.sender);
    }

    /// @notice Close the commit phase once its deadline passes.
    function closeCommit(uint256 disputeId) external {
        Dispute storage d = _requireDispute(disputeId);
        _requirePhase(disputeId, d, Phase.Commit);
        if (block.timestamp <= d.phaseDeadline) revert DeadlineNotReached(d.phaseDeadline);

        d.phase = Phase.Reveal;
        d.phaseDeadline = uint64(block.timestamp) + config.revealWindow();
    }

    /**
     * @notice Reveal the ruling behind your commitment.
     * @dev The hash binds the dispute, the round and the juror, so a commitment
     *      cannot be lifted from one case into another or replayed by someone
     *      else (sec. 30).
     */
    function revealVote(uint256 disputeId, Ruling ruling, bytes32 salt) external {
        Dispute storage d = _requireDispute(disputeId);
        _requirePhase(disputeId, d, Phase.Reveal);
        if (block.timestamp > d.phaseDeadline) revert DeadlinePassed(d.phaseDeadline);
        if (!isSeated[disputeId][msg.sender]) revert NotSeated(msg.sender);
        if (ruling == Ruling.None) revert RulingNotAllowed(ruling);

        bytes32 commitment = commitmentOf[disputeId][msg.sender];
        if (commitment == bytes32(0)) revert NothingCommitted(msg.sender);
        if (revealedVote[disputeId][msg.sender] != Ruling.None) revert AlreadyRevealed(msg.sender);

        bytes32 expected = hashVote(disputeId, d.round, msg.sender, ruling, salt);
        if (commitment != expected) revert CommitmentMismatch(expected, commitment);

        revealedVote[disputeId][msg.sender] = ruling;
        tally[disputeId][uint8(ruling)] += 1;
        d.revealed += 1;
        emit VoteRevealed(disputeId, msg.sender, ruling);
    }

    /// @notice The commitment a juror must produce (sec. 30).
    function hashVote(uint256 disputeId, uint8 round, address juror, Ruling ruling, bytes32 salt)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(disputeId, round, juror, ruling, salt));
    }

    /**
     * @notice Close the reveal phase and settle on a ruling.
     * @dev Jurors who committed and did not reveal are slashed; everyone else is
     *      released untouched, whichever way they voted (invariant sec. 33-14).
     *      With nothing revealed there is no ruling to reach, and the dispute
     *      fails rather than inventing one.
     */
    function closeReveal(uint256 disputeId) external nonReentrant {
        Dispute storage d = _requireDispute(disputeId);
        _requirePhase(disputeId, d, Phase.Reveal);
        if (block.timestamp <= d.phaseDeadline) revert DeadlineNotReached(d.phaseDeadline);

        address[] storage panel = _panel[disputeId];
        for (uint256 i = 0; i < panel.length; i++) {
            address juror = panel[i];
            bool committed = commitmentOf[disputeId][juror] != bytes32(0);
            bool revealed = revealedVote[disputeId][juror] != Ruling.None;

            if (committed && !revealed) {
                jurors.slashForNonReveal(disputeId, juror);
            } else {
                jurors.release(disputeId, juror);
            }

            // sec. 25: a first *finalised* jury round is what qualifies a juror,
            // so it is reported here and not at commit or reveal. A juror who
            // stayed silent did not serve and does not qualify.
            if (revealed) _qualify(juror);
        }

        if (d.revealed == 0) {
            d.phase = Phase.Failed;
            d.phaseDeadline = 0;
            emit DisputeFailed(disputeId, "no juror revealed");
            return;
        }

        (Ruling winner, uint16 votes) = _winner(disputeId);
        d.ruling = winner;
        d.phase = Phase.Ruled;
        d.phaseDeadline = 0;
        emit DisputeRuled(disputeId, d.round, winner, votes);
    }

    /**
     * @dev Highest tally wins. A tie resolves to `Refuse` — the outcome sec. 30
     *      provides for a panel that could not decide, which is exactly what a
     *      tie is. Picking the numerically lower ruling instead would hand the
     *      decision to the order of an enum.
     */
    function _winner(uint256 disputeId) internal view returns (Ruling winner, uint16 votes) {
        uint16 best = 0;
        uint8 bestCode = 0;
        bool tied = false;

        for (uint8 code = uint8(Ruling.Customer100); code <= uint8(Ruling.Refuse); code++) {
            uint16 count = tally[disputeId][code];
            if (count > best) {
                best = count;
                bestCode = code;
                tied = false;
            } else if (count == best && count > 0) {
                tied = true;
            }
        }
        return tied ? (Ruling.Refuse, best) : (Ruling(bestCode), best);
    }

    // --------------------------------------------------------------------
    // Reading
    // --------------------------------------------------------------------

    function disputeOf(uint256 disputeId) external view returns (Dispute memory) {
        return _disputes[disputeId];
    }

    function panelOf(uint256 disputeId) external view returns (address[] memory) {
        return _panel[disputeId];
    }

    function panelSize(uint256 disputeId) external view returns (uint256) {
        return _panel[disputeId].length;
    }

    /// @notice Panel size for a round: 3, then 5, then 7 (sec. 28).
    function _panelSize(uint8 round) internal view returns (uint256) {
        if (round <= 1) return config.juryFirstSize();
        if (round == 2) return config.juryAppeal1Size();
        return config.juryAppeal2Size();
    }

    function _requireDispute(uint256 disputeId) internal view returns (Dispute storage d) {
        d = _disputes[disputeId];
        if (d.phase == Phase.None) revert UnknownDispute(disputeId);
    }

    function _requirePhase(uint256 disputeId, Dispute storage d, Phase expected) internal view {
        if (d.phase != expected) revert WrongPhase(disputeId, d.phase, expected);
    }

    /**
     * @dev Failure-tolerant by construction: `recordQualification` reverts on a
     *      juror who already qualified, which is every round after their first.
     *      A panel sweep must not be able to fail over that, or a single repeat
     *      juror would leave the whole dispute stuck in `Reveal` with every other
     *      juror's collateral still locked (sec. 25).
     */
    function _qualify(address juror) internal {
        if (address(referral) == address(0)) return;

        bytes memory data = abi.encodeCall(Referral.recordQualification, (juror, Referral.Role.Juror));
        // slither-disable-next-line low-level-calls,calls-loop
        (bool ok,) = address(referral).call(data);
        if (!ok) emit ReferralReportFailed(juror, data);
    }

    function _gcd(uint256 a, uint256 b) internal pure returns (uint256) {
        while (b != 0) {
            (a, b) = (b, a % b);
        }
        return a;
    }
}
