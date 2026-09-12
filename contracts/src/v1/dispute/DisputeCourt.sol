// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {ProtocolAccessManager} from "../access/ProtocolAccessManager.sol";
import {ProtocolConfig} from "../config/ProtocolConfig.sol";
import {IRandomnessAdapter} from "../randomness/IRandomnessAdapter.sol";
import {JurorPool} from "./JurorPool.sol";
import {Referral} from "../rewards/Referral.sol";
import {DeliveryHub} from "../hub/DeliveryHub.sol";
import {FallbackCommittee} from "./FallbackCommittee.sol";

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

    /// @notice The last round sec. 28 provides for: first, appeal 1, appeal 2.
    uint8 public constant MAX_ROUND = 3;

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
        Failed,
        // terminal from here down
        Settled,
        Abandoned
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
        /// @dev Arbitration fees collected across every round (sec. 28).
        uint128 feesHeld;
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

    /// @notice The delivery ledger a ruling settles against.
    DeliveryHub public immutable hub;

    /// @notice sec. 31's last-resort liveness signer. May be zero: a deployment
    ///         without a committee still works, it simply has no fallback.
    FallbackCommittee public immutable committee;

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

    /**
     * @notice At most one dispute per delivery, by delivery id. Zero means none.
     * @dev Stored as `disputeId + 1` so that dispute 0 is distinguishable from
     *      "no dispute", which is why nothing reads this mapping directly.
     */
    mapping(uint256 => uint256) internal _disputeOfDelivery;

    /// @notice The bond posted for a round, and by whom (sec. 28).
    mapping(uint256 => mapping(uint8 => uint128)) public bondOf;
    mapping(uint256 => mapping(uint8 => address)) public bondPayerOf;

    /// @notice What each round decided, kept so an appeal can be judged against it.
    mapping(uint256 => mapping(uint8 => Ruling)) public rulingOfRound;

    /// @notice Pull-payment balances for bonds and fees (sec. 18.2).
    mapping(address => uint256) public claimable;

    /// @notice What `claimable` adds up to. The contract may never hold less.
    uint256 public totalOwed;

    // --------------------------------------------------------------------
    // Events and errors
    // --------------------------------------------------------------------

    event DisputeOpened(uint256 indexed disputeId, uint256 indexed deliveryId, address indexed opener);
    event EvidenceSubmitted(uint256 indexed disputeId, address indexed submitter, bytes32 commitment);
    event DrawRequested(uint256 indexed disputeId, uint64 requestId, uint256 candidates, uint256 feePaid);
    event PanelSeated(uint256 indexed disputeId, uint8 round, address[] panel);
    event Appealed(uint256 indexed disputeId, uint8 round, address indexed appellant, Ruling appealedFrom);
    event DisputeSettled(
        uint256 indexed disputeId,
        uint256 indexed deliveryId,
        Ruling ruling,
        uint16 customerBps,
        uint96 toCustomer,
        uint96 toCourier
    );
    event DisputeAbandoned(uint256 indexed disputeId, uint256 indexed deliveryId);
    event ResolvedByCommittee(uint256 indexed disputeId, uint8 round, Ruling ruling);
    event Credited(address indexed account, uint256 amount, string reason);
    event Claimed(address indexed account, uint256 amount);
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
    error NotAParty(address caller);
    error DisputeAlreadyOpen(uint256 deliveryId, uint256 disputeId);
    error AppealWindowClosed(uint64 closedAt);
    error AppealWindowOpen(uint64 closesAt);
    error NoFurtherAppeal(uint8 round);
    error PaymentTooLow(uint256 required, uint256 provided);
    error NothingToClaim(address account);
    error DeliveryStillDisputed(uint256 deliveryId);
    error Insolvent(uint256 owed, uint256 held);
    error CommitteeNotConfigured();

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
        Referral referral_,
        DeliveryHub hub_,
        FallbackCommittee committee_
    ) {
        if (address(accessManager_) == address(0)) revert ZeroAddress();
        if (address(config_) == address(0)) revert ZeroAddress();
        if (address(jurors_) == address(0)) revert ZeroAddress();
        if (address(randomness_) == address(0)) revert ZeroAddress();
        if (address(hub_) == address(0)) revert ZeroAddress();

        accessManager = accessManager_;
        config = config_;
        jurors = jurors_;
        randomness = randomness_;
        hub = hub_;
        // Both may be zero: a deployment without a referral programme still
        // judges disputes, and one without a committee simply has no fallback.
        // Everything else above is load-bearing and is checked.
        referral = referral_;
        committee = committee_;
    }

    /**
     * @dev Bonds and fees are other people's money held until a case closes. The
     *      contract must never be able to pay one claimant out of another's
     *      balance, so every path that moves value is checked against the total
     *      owed rather than against the raw balance.
     */
    modifier solvent() {
        _;
        if (address(this).balance < totalOwed) revert Insolvent(totalOwed, address(this).balance);
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
    function open(uint256 deliveryId) external payable nonReentrant solvent returns (uint256 disputeId) {
        uint256 existing = _disputeOfDelivery[deliveryId];
        if (existing != 0) revert DisputeAlreadyOpen(deliveryId, existing - 1);

        (address customer, address courier) = hub.partiesOf(deliveryId);
        if (msg.sender != customer && msg.sender != courier) revert NotAParty(msg.sender);

        disputeId = nextDisputeId++;
        _disputeOfDelivery[deliveryId] = disputeId + 1;

        uint256 excess = _takePayment(disputeId, 1, msg.sender);

        _disputes[disputeId] = Dispute({
            deliveryId: deliveryId,
            opener: msg.sender,
            phase: Phase.Evidence,
            round: 1,
            phaseDeadline: uint64(block.timestamp) + config.evidenceWindow(),
            drawRequestId: 0,
            ruling: Ruling.None,
            committed: 0,
            revealed: 0,
            feesHeld: config.arbitrationFee(1)
        });
        emit DisputeOpened(disputeId, deliveryId, msg.sender);

        // The hub is told last, once this contract's own books are closed. It
        // decides whether the delivery is in a state a jury may judge and moves
        // it out of reach of the deterministic exits; it reverts if not, and a
        // revert takes everything above with it. Nothing here duplicates the
        // hub's state machine, and no state of ours is written after a call out.
        hub.openDispute(deliveryId);
        if (excess > 0) _refund(msg.sender, excess);
    }

    /**
     * @dev Records one round's arbitration fee and bond (sec. 28) and reports
     *      the overpayment for the caller to return once its own writes are
     *      done. Anything above the two is owed straight back rather than kept:
     *      somebody who overpays a fixed price has not made a donation.
     */
    function _takePayment(uint256 disputeId, uint8 round, address payer) internal returns (uint256 excess) {
        uint128 fee = config.arbitrationFee(round);
        uint128 bond = config.disputeBond(round);
        uint256 required = uint256(fee) + bond;
        if (msg.value < required) revert PaymentTooLow(required, msg.value);

        bondOf[disputeId][round] = bond;
        bondPayerOf[disputeId][round] = payer;
        // Fees and bonds are owed to someone from this moment: the bond to its
        // payer unless it is forfeited, the fee to the treasury unless the case
        // is abandoned. Counting them now is what makes `solvent` mean anything.
        totalOwed += required;

        return msg.value - required;
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

        uint256 candidates = jurors.takeSnapshot(_roundKey(disputeId, d.round));
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

        uint256 key = _roundKey(disputeId, d.round);
        uint256 size = jurors.snapshotSize(key);
        uint256 wanted = _panelSize(d.round);
        address[] storage panel = _panel[key];

        // A stride coprime with the set size visits every position exactly once,
        // so a juror cannot be drawn twice and the walk cannot cycle early.
        //
        // The `size > 1` guard is not a nicety: picking a stride out of
        // `% (size - 1)` divides by zero when exactly one candidate stood, and a
        // panel that is merely impossible to fill must fail as `PanelTooSmall`
        // below rather than as a panic. With one candidate every stride is
        // trivially coprime, so there is nothing to search for either. An empty
        // snapshot never reaches here at all -- `takeSnapshot` refuses one.
        //
        // Slither reads the modulus here as a weak PRNG. It is not a source of
        // randomness at all: `value` arrived from the provider (sec. 29), and
        // these lines only turn that one number into a start and a step over an
        // array. The baseline rules out blockhash explicitly, and nothing here
        // reaches for one.
        // slither-disable-start weak-prng
        uint256 start = uint256(value) % size;
        uint256 stride = 1;
        if (size > 1) {
            stride = (uint256(keccak256(abi.encode(value, "stride"))) % (size - 1)) + 1;
            // The equality is exact by nature: "is this the last stride we
            // could try", not an approximation of it. Slither reads a strict
            // comparison inside a search loop as a rounding hazard.
            while (_gcd(stride, size) != 1) {
                // slither-disable-next-line incorrect-equality
                stride = stride == size - 1 ? 1 : stride + 1;
            }
        }

        uint256 cursor = start;
        for (uint256 i = 0; i < size && panel.length < wanted; i++) {
            address candidate = jurors.snapshotAt(key, cursor);
            cursor = (cursor + stride) % size;
            // slither-disable-end weak-prng

            if (isSeated[key][candidate]) continue;
            if (!jurors.seat(key, candidate)) continue;

            // `isSeated` is written after `jurors.seat` returns, which Slither
            // reads as cross-function reentrancy against `commitVote` and
            // `revealVote`. The callee is `JurorPool`, fixed at construction,
            // holding no untrusted code and making no call of its own; there is
            // no path from it back into this contract. Ordering the write first
            // would mean rolling it back when seating is refused, which is a
            // write after the same call by another name. The function is
            // `nonReentrant` regardless.
            // slither-disable-next-line reentrancy-no-eth
            isSeated[key][candidate] = true;
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
    // Appeals and settlement (sec. 28, sec. 30, sec. 31)
    // --------------------------------------------------------------------

    /**
     * @notice Ask for a larger panel to look again (sec. 28).
     * @dev The escalation is 3 -> 5 -> 7 and stops there: sec. 28's schedule has
     *      three rows and no fourth, so round 3 is final by construction rather
     *      than by a deadline.
     *
     *      An appeal reopens evidence. sec. 28's diagram does not say to, but a
     *      party who lost because something was missing has nothing to gain from
     *      a second panel reading the same file, and the long stop is sized for
     *      three full rounds including their evidence windows.
     *
     *      The bond is what keeps this from being a free option. It is returned
     *      if the larger panel disagrees with the smaller one, and forfeited to
     *      the treasury if it does not — which is the difference between paying
     *      to be heard and paying to delay.
     */
    function appeal(uint256 disputeId) external payable nonReentrant solvent {
        Dispute storage d = _requireDispute(disputeId);
        _requirePhase(disputeId, d, Phase.Ruled);
        if (block.timestamp > d.phaseDeadline) revert AppealWindowClosed(d.phaseDeadline);
        if (d.round >= MAX_ROUND) revert NoFurtherAppeal(d.round);

        (address customer, address courier) = hub.partiesOf(d.deliveryId);
        if (msg.sender != customer && msg.sender != courier) revert NotAParty(msg.sender);

        Ruling appealedFrom = d.ruling;
        uint8 next = d.round + 1;
        d.round = next;
        d.ruling = Ruling.None;
        d.committed = 0;
        d.revealed = 0;
        d.drawRequestId = 0;
        d.phase = Phase.Evidence;
        d.phaseDeadline = uint64(block.timestamp) + config.evidenceWindow();

        uint256 excess = _takePayment(disputeId, next, msg.sender);
        d.feesHeld += config.arbitrationFee(next);

        emit Appealed(disputeId, next, msg.sender, appealedFrom);
        if (excess > 0) _refund(msg.sender, excess);
    }

    /**
     * @notice Turn a standing ruling into money (sec. 30, sec. 18.2).
     * @dev Permissionless, and only after the appeal window has closed, so the
     *      losing party always has their chance to escalate before anything
     *      moves. Round 3 has no further appeal, so it settles as soon as its
     *      window elapses like any other.
     *
     *      This is the one place a ruling becomes a payment, and it can run only
     *      once: the hub refuses `settleByRuling` on a delivery that is no longer
     *      `Disputed`, and this dispute leaves in a terminal phase.
     */
    function finalise(uint256 disputeId) external nonReentrant solvent {
        Dispute storage d = _requireDispute(disputeId);
        _requirePhase(disputeId, d, Phase.Ruled);
        if (block.timestamp <= d.phaseDeadline) revert AppealWindowOpen(d.phaseDeadline);

        _settle(disputeId, d, d.ruling);
    }

    /**
     * @notice End a case the jury could not decide (sec. 31).
     * @dev Only from `Failed`: the randomness never arrived, or nobody revealed.
     *      A running dispute is out of the committee's reach entirely, which is
     *      what keeps a liveness mechanism from becoming a veto.
     *
     *      The committee's signature carries a ruling code and nothing else. It
     *      cannot name a recipient or an amount, so the worst a captured
     *      committee can do is pick badly among the six answers a jury could
     *      have picked among — see `FallbackCommittee`.
     */
    function resolveByCommittee(
        uint256 disputeId,
        FallbackCommittee.Decision calldata decision,
        bytes calldata signature
    ) external nonReentrant solvent {
        Dispute storage d = _requireDispute(disputeId);
        _requirePhase(disputeId, d, Phase.Failed);
        if (address(committee) == address(0)) revert CommitteeNotConfigured();

        uint8 code = committee.requireDecision(disputeId, d.round, decision, signature);
        Ruling ruling = Ruling(code);

        d.ruling = ruling;
        rulingOfRound[disputeId][d.round] = ruling;
        emit ResolvedByCommittee(disputeId, d.round, ruling);

        _settle(disputeId, d, ruling);
    }

    /**
     * @notice Give up on a dispute whose delivery the hub already settled.
     * @dev The hub's long stop fires when a court goes quiet for the whole of
     *      `disputeWindow`. When it has, there is nothing left to rule on: the
     *      escrow is gone and no ruling can be carried out. Everything collected
     *      goes back to whoever paid it, because nothing was adjudicated and a
     *      fee for a trial that never concluded is not earned.
     *
     *      Permissionless on purpose. A case stuck in `Failed` with no committee
     *      would otherwise hold its bonds forever.
     */
    function abandon(uint256 disputeId) external nonReentrant solvent {
        Dispute storage d = _requireDispute(disputeId);
        if (d.phase >= Phase.Settled) revert WrongPhase(disputeId, d.phase, Phase.Ruled);
        if (hub.deliveryOf(d.deliveryId).state == DeliveryHub.State.Disputed) {
            revert DeliveryStillDisputed(d.deliveryId);
        }

        for (uint8 round = 1; round <= d.round; round++) {
            _refundBond(disputeId, round);
        }
        if (d.feesHeld > 0) {
            _credit(d.opener, d.feesHeld, "fees returned, nothing adjudicated");
            d.feesHeld = 0;
        }

        d.phase = Phase.Abandoned;
        d.phaseDeadline = 0;
        emit DisputeAbandoned(disputeId, d.deliveryId);
    }

    /// @dev The single path from a ruling to money. Everything else routes here.
    function _settle(uint256 disputeId, Dispute storage d, Ruling ruling) internal {
        uint16 customerBps = _customerShareBps(ruling);
        (uint96 toCustomer, uint96 toCourier) = hub.settleByRuling(d.deliveryId, customerBps);

        // The first round's bond is for taking part, not for being right, and
        // comes back either way. Each appeal bond is a wager on the larger panel
        // disagreeing: returned when it did, forfeited when it did not.
        _refundBond(disputeId, 1);
        for (uint8 round = 2; round <= d.round; round++) {
            if (rulingOfRound[disputeId][round] != rulingOfRound[disputeId][round - 1]) {
                _refundBond(disputeId, round);
            } else {
                _forfeitBond(disputeId, round);
            }
        }

        if (d.feesHeld > 0) {
            _credit(config.treasury(), d.feesHeld, "arbitration fees");
            d.feesHeld = 0;
        }

        d.phase = Phase.Settled;
        d.phaseDeadline = 0;
        emit DisputeSettled(disputeId, d.deliveryId, ruling, customerBps, toCustomer, toCourier);
    }

    /**
     * @notice The customer's share of the escrow for each sec. 30 outcome.
     * @dev `Refuse` is the panel declining to decide, and the protocol's answer
     *      whenever it cannot establish that the courier performed is to return
     *      the escrow — the same answer a timed-out return or a stalled dispute
     *      gets. Reading it as a courier win would reward declining to rule.
     */
    function _customerShareBps(Ruling ruling) internal pure returns (uint16) {
        if (ruling == Ruling.Customer100) return 10_000;
        if (ruling == Ruling.Customer75) return 7_500;
        if (ruling == Ruling.Split50) return 5_000;
        if (ruling == Ruling.Customer25) return 2_500;
        if (ruling == Ruling.Courier100) return 0;
        return 10_000;
    }

    // --------------------------------------------------------------------
    // Money (sec. 18.2: pulled, never pushed)
    // --------------------------------------------------------------------

    /// @notice Withdraw bonds returned to you, or fees owed to the treasury.
    function claim() external nonReentrant {
        uint256 amount = claimable[msg.sender];
        if (amount == 0) revert NothingToClaim(msg.sender);

        claimable[msg.sender] = 0;
        totalOwed -= amount;
        emit Claimed(msg.sender, amount);

        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert RefundFailed(msg.sender, amount);
    }

    function _refundBond(uint256 disputeId, uint8 round) internal {
        uint128 bond = bondOf[disputeId][round];
        if (bond == 0) return;

        bondOf[disputeId][round] = 0;
        _credit(bondPayerOf[disputeId][round], bond, "bond returned");
    }

    function _forfeitBond(uint256 disputeId, uint8 round) internal {
        uint128 bond = bondOf[disputeId][round];
        if (bond == 0) return;

        bondOf[disputeId][round] = 0;
        _credit(config.treasury(), bond, "appeal bond forfeited");
    }

    /// @dev Moves an already-counted liability from the contract to an account.
    function _credit(address account, uint256 amount, string memory reason) internal {
        claimable[account] += amount;
        emit Credited(account, amount, reason);
    }

    /// @dev Pays out immediately. Used only for overpayment, which was never owed.
    function _refund(address to, uint256 amount) internal {
        // slither-disable-next-line arbitrary-send-eth
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert RefundFailed(to, amount);
    }

    // --------------------------------------------------------------------
    // Voting (sec. 30)
    // --------------------------------------------------------------------

    /// @notice Commit to a ruling without revealing it.
    function commitVote(uint256 disputeId, bytes32 voteHash) external {
        Dispute storage d = _requireDispute(disputeId);
        _requirePhase(disputeId, d, Phase.Commit);
        if (block.timestamp > d.phaseDeadline) revert DeadlinePassed(d.phaseDeadline);
        uint256 key = _roundKey(disputeId, d.round);
        if (!isSeated[key][msg.sender]) revert NotSeated(msg.sender);
        if (commitmentOf[key][msg.sender] != bytes32(0)) revert AlreadyCommitted(msg.sender);

        commitmentOf[key][msg.sender] = voteHash;
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
        uint256 key = _roundKey(disputeId, d.round);
        if (!isSeated[key][msg.sender]) revert NotSeated(msg.sender);
        if (ruling == Ruling.None) revert RulingNotAllowed(ruling);

        bytes32 commitment = commitmentOf[key][msg.sender];
        if (commitment == bytes32(0)) revert NothingCommitted(msg.sender);
        if (revealedVote[key][msg.sender] != Ruling.None) revert AlreadyRevealed(msg.sender);

        bytes32 expected = hashVote(disputeId, d.round, msg.sender, ruling, salt);
        if (commitment != expected) revert CommitmentMismatch(expected, commitment);

        revealedVote[key][msg.sender] = ruling;
        tally[key][uint8(ruling)] += 1;
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

        uint256 key = _roundKey(disputeId, d.round);
        address[] storage panel = _panel[key];
        for (uint256 i = 0; i < panel.length; i++) {
            address juror = panel[i];
            bool committed = commitmentOf[key][juror] != bytes32(0);
            bool revealed = revealedVote[key][juror] != Ruling.None;

            if (committed && !revealed) {
                jurors.slashForNonReveal(key, juror);
            } else {
                jurors.release(key, juror);
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

        (Ruling winner, uint16 votes) = _winner(key);
        d.ruling = winner;
        rulingOfRound[disputeId][d.round] = winner;
        d.phase = Phase.Ruled;
        // The ruling stands until the appeal window closes; `finalise` will not
        // move money before then, and `appeal` will not be accepted after.
        d.phaseDeadline = uint64(block.timestamp) + config.appealWindow();
        emit DisputeRuled(disputeId, d.round, winner, votes);
    }

    /**
     * @dev Highest tally wins. A tie resolves to `Refuse` — the outcome sec. 30
     *      provides for a panel that could not decide, which is exactly what a
     *      tie is. Picking the numerically lower ruling instead would hand the
     *      decision to the order of an enum.
     */
    function _winner(uint256 key) internal view returns (Ruling winner, uint16 votes) {
        uint16 best = 0;
        uint8 bestCode = 0;
        bool tied = false;

        for (uint8 code = uint8(Ruling.Customer100); code <= uint8(Ruling.Refuse); code++) {
            uint16 count = tally[key][code];
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

    /// @notice The panel for the dispute's current round.
    function panelOf(uint256 disputeId) external view returns (address[] memory) {
        return _panel[_roundKey(disputeId, _disputes[disputeId].round)];
    }

    /// @notice The panel that sat for a particular round, after an appeal moved on.
    function panelOfRound(uint256 disputeId, uint8 round) external view returns (address[] memory) {
        return _panel[_roundKey(disputeId, round)];
    }

    function panelSize(uint256 disputeId) external view returns (uint256) {
        return _panel[_roundKey(disputeId, _disputes[disputeId].round)].length;
    }

    /// @notice The dispute over `deliveryId`, if one was ever opened.
    function disputeOfDelivery(uint256 deliveryId) external view returns (bool exists, uint256 disputeId) {
        uint256 stored = _disputeOfDelivery[deliveryId];
        return (stored != 0, stored == 0 ? 0 : stored - 1);
    }

    /**
     * @notice The key every per-round mapping is filed under.
     * @dev A dispute that is appealed draws a second panel and runs a second
     *      vote, and neither may see the first one's storage. Keying by the pair
     *      rather than by the dispute alone is what makes each round its own
     *      case: its own frozen candidate set, its own seats, its own
     *      commitments, its own tally. The same key is the juror pool's draw id,
     *      so a juror who sat in round one gives up that seat and may be drawn
     *      again for round two on equal terms with everyone else.
     */
    function _roundKey(uint256 disputeId, uint8 round) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(disputeId, round)));
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

    /// @dev Euclid. The modulus is arithmetic, not entropy; see `seatPanel`.
    // slither-disable-next-line weak-prng
    function _gcd(uint256 a, uint256 b) internal pure returns (uint256) {
        while (b != 0) {
            (a, b) = (b, a % b);
        }
        return a;
    }
}
