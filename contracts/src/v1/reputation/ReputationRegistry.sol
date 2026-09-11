// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ProtocolAccessManager} from "../access/ProtocolAccessManager.sol";

/**
 * @title ReputationRegistry
 * @notice Courier reputation: a 0-1000 score and a separate confidence level.
 * @dev Baseline refs: sec. 19 (score, weights, versioning, confidence), sec. 13
 *      (on-time is judged against the courier's own accepted ETA), sec. 20
 *      (customer rating is one input, not the score), sec. 22 (ranking is not
 *      computed on chain).
 *
 *      ## Score and confidence are two different questions
 *
 *      The score asks "how well does this courier perform"; confidence asks "how
 *      much history is that judgement based on". Keeping them apart is what stops
 *      a courier with one perfect delivery from reading the same as one with
 *      hundreds (sec. 19) — their scores may be close, but their confidence is
 *      not, and a consumer can weigh accordingly.
 *
 *      Confidence is deliberately not folded into the score as a multiplier: that
 *      would make a good newcomer indistinguishable from a mediocre veteran, and
 *      the two need different responses.
 *
 *      ## Nothing here sorts
 *
 *      sec. 22 puts ranking in an indexer, and this contract has no array of
 *      couriers, no ordering and no iteration of any kind — only per-courier
 *      counters. Ranking is derived off-chain from the events emitted here.
 *      A leaderboard that sorts stored couriers is quadratic in their number and
 *      stops working exactly when the protocol succeeds.
 *
 *      ## Neutral priors, not perfect ones
 *
 *      A courier with no history has no evidence either way, so the rate-shaped
 *      components start at the midpoint rather than at full marks. Starting them
 *      perfect would hand a brand-new account the maximum score, which is the
 *      opposite of what a reputation system is for.
 *
 *      ## Versioned from the first line
 *
 *      `ALGORITHM_VERSION` is emitted with every update. When the formula
 *      changes, historical scores stay interpretable because each one says which
 *      formula produced it. Weights are compile-time constants: changing them is
 *      a deliberate new version, not a configuration tweak.
 */
contract ReputationRegistry {
    // --------------------------------------------------------------------
    // Constants
    // --------------------------------------------------------------------

    /// @notice Bumped whenever the formula below changes.
    uint16 public constant ALGORITHM_VERSION = 1;

    uint256 internal constant SCALE = 10_000;
    uint256 public constant MAX_SCORE = 1_000;
    uint256 public constant MAX_CONFIDENCE = 1_000;

    /// @dev sec. 19 weight table, in basis points. Must sum to SCALE.
    uint256 internal constant W_SUCCESS = 3_000; // 30%
    uint256 internal constant W_RATING = 2_000; // 20%
    uint256 internal constant W_ON_TIME = 1_500; // 15%
    uint256 internal constant W_DISPUTE = 1_500; // 15%
    uint256 internal constant W_CANCELLATION = 1_000; // 10%
    uint256 internal constant W_EXPERIENCE = 1_000; // 10%

    /// @dev Midpoint used where there is no evidence yet.
    uint256 internal constant NEUTRAL = SCALE / 2;

    /// @notice Completed deliveries at which confidence reaches its maximum.
    uint32 public constant FULL_CONFIDENCE_AT = 100;

    uint8 public constant MIN_RATING = 1;
    uint8 public constant MAX_RATING = 5;

    // --------------------------------------------------------------------
    // Storage
    // --------------------------------------------------------------------

    /**
     * @param completed        Deliveries that ended in the success state.
     * @param onTime           Of those, ones that met the accepted ETA (sec. 13).
     * @param courierFailed    Returns and cancellations attributable to the courier.
     * @param cancelledByCourier Assignments the courier abandoned before delivery.
     * @param assignments      Every delivery the courier was selected for.
     * @param disputesWon      Disputes resolved in the courier's favour.
     * @param disputesLost     Disputes resolved against them.
     * @param ratingCount      Number of customer ratings received.
     * @param ratingSum        Sum of those ratings, 1-5 each.
     */
    struct Record {
        uint32 completed;
        uint32 onTime;
        uint32 courierFailed;
        uint32 cancelledByCourier;
        uint32 assignments;
        uint32 disputesWon;
        uint32 disputesLost;
        uint32 ratingCount;
        uint64 ratingSum;
    }

    ProtocolAccessManager public immutable accessManager;

    mapping(address => Record) internal _records;

    /// @notice Deliveries already rated, so one delivery yields one rating (sec. 20).
    mapping(uint256 => bool) public deliveryRated;

    // --------------------------------------------------------------------
    // Events
    // --------------------------------------------------------------------

    /// @dev The indexer builds every ranking from these (sec. 22).
    event OutcomeRecorded(
        address indexed courier, uint256 indexed deliveryId, Outcome outcome, bool onTime, uint16 version
    );
    event CourierRated(address indexed courier, uint256 indexed deliveryId, uint8 rating, uint16 version);
    event ReputationUpdated(address indexed courier, uint16 score, uint16 confidence, uint16 version);

    enum Outcome {
        None,
        Completed,
        Returned,
        CancelledByCourier,
        Expired
    }

    // --------------------------------------------------------------------
    // Errors
    // --------------------------------------------------------------------

    error ZeroAddress();
    error RatingOutOfRange(uint8 rating);
    error DeliveryAlreadyRated(uint256 deliveryId);
    error UnknownOutcome();

    // --------------------------------------------------------------------
    // Wiring
    // --------------------------------------------------------------------

    constructor(ProtocolAccessManager accessManager_) {
        if (address(accessManager_) == address(0)) revert ZeroAddress();
        accessManager = accessManager_;
    }

    /**
     * @dev Writes come only from protocol contracts holding the role, never from
     *      an EOA: a key that could write reputation could manufacture standing.
     */
    modifier onlyReporter() {
        accessManager.requireRole(accessManager.REPUTATION_REPORTER_ROLE(), msg.sender);
        _;
    }

    // --------------------------------------------------------------------
    // Recording
    // --------------------------------------------------------------------

    /**
     * @notice Record that a courier was selected for a delivery.
     * @dev Counted separately from outcomes so the cancellation rate has a
     *      denominator that includes assignments still in flight.
     */
    function recordAssignment(address courier) external onlyReporter {
        if (courier == address(0)) revert ZeroAddress();
        _records[courier].assignments += 1;
        _emitUpdate(courier);
    }

    /**
     * @notice Record how a delivery ended for its courier.
     * @param onTime Whether the proof arrived within the ETA the courier itself
     *        accepted in its bid (sec. 13), not within any protocol-wide constant.
     */
    function recordOutcome(address courier, uint256 deliveryId, Outcome outcome, bool onTime) external onlyReporter {
        if (courier == address(0)) revert ZeroAddress();
        Record storage r = _records[courier];

        if (outcome == Outcome.Completed) {
            r.completed += 1;
            if (onTime) r.onTime += 1;
        } else if (outcome == Outcome.Returned) {
            // A return is a failure to deliver, but not necessarily the courier's
            // fault, and sec. 13 forbids treating lateness alone as fault. It
            // counts against the success rate and stops there; blame needs the
            // dispute court.
            r.courierFailed += 1;
        } else if (outcome == Outcome.CancelledByCourier) {
            r.courierFailed += 1;
            r.cancelledByCourier += 1;
        } else if (outcome != Outcome.Expired) {
            revert UnknownOutcome();
        }

        emit OutcomeRecorded(courier, deliveryId, outcome, onTime, ALGORITHM_VERSION);
        _emitUpdate(courier);
    }

    /// @notice Record a dispute resolution (P4 wires this).
    function recordDispute(address courier, bool courierWon) external onlyReporter {
        if (courier == address(0)) revert ZeroAddress();
        if (courierWon) _records[courier].disputesWon += 1;
        else _records[courier].disputesLost += 1;
        _emitUpdate(courier);
    }

    /**
     * @notice Record one customer rating for one delivery (sec. 20).
     * @dev The caller is responsible for checking that the rater is the delivery's
     *      customer and that the rating window is open; this contract enforces the
     *      range and the one-rating-per-delivery rule.
     */
    function recordRating(address courier, uint256 deliveryId, uint8 rating) external onlyReporter {
        if (courier == address(0)) revert ZeroAddress();
        if (rating < MIN_RATING || rating > MAX_RATING) revert RatingOutOfRange(rating);
        if (deliveryRated[deliveryId]) revert DeliveryAlreadyRated(deliveryId);

        deliveryRated[deliveryId] = true;
        Record storage r = _records[courier];
        r.ratingCount += 1;
        r.ratingSum += rating;

        emit CourierRated(courier, deliveryId, rating, ALGORITHM_VERSION);
        _emitUpdate(courier);
    }

    // --------------------------------------------------------------------
    // Reading
    // --------------------------------------------------------------------

    function recordOf(address courier) external view returns (Record memory) {
        return _records[courier];
    }

    /// @notice The courier's 0-1000 score under `ALGORITHM_VERSION`.
    function scoreOf(address courier) public view returns (uint16) {
        Record memory r = _records[courier];

        uint256 weighted = W_SUCCESS * _successRate(r) + W_RATING * _ratingRate(r) + W_ON_TIME * _onTimeRate(r)
            + W_DISPUTE * _disputeRate(r) + W_CANCELLATION * _cancellationRate(r) + W_EXPERIENCE * _experienceRate(r);

        // weighted is at most SCALE * SCALE, so this cannot exceed MAX_SCORE.
        return uint16((weighted * MAX_SCORE) / (SCALE * SCALE));
    }

    /// @notice How much history the score rests on, 0-1000 (sec. 19).
    function confidenceOf(address courier) public view returns (uint16) {
        return uint16((_experienceRate(_records[courier]) * MAX_CONFIDENCE) / SCALE);
    }

    function averageRatingBps(address courier) external view returns (uint256) {
        Record memory r = _records[courier];
        if (r.ratingCount == 0) return 0;
        return (uint256(r.ratingSum) * SCALE) / r.ratingCount;
    }

    // --------------------------------------------------------------------
    // Components — each returns 0..SCALE
    // --------------------------------------------------------------------

    /// @dev No finished deliveries yet means no evidence, so the midpoint.
    function _successRate(Record memory r) internal pure returns (uint256) {
        uint256 finished = uint256(r.completed) + r.courierFailed;
        if (finished == 0) return NEUTRAL;
        return (uint256(r.completed) * SCALE) / finished;
    }

    /// @dev Ratings run 1-5, so 1 maps to 0 and 5 to SCALE.
    function _ratingRate(Record memory r) internal pure returns (uint256) {
        if (r.ratingCount == 0) return NEUTRAL;
        uint256 avgScaled = (uint256(r.ratingSum) * SCALE) / r.ratingCount;
        uint256 floorScaled = uint256(MIN_RATING) * SCALE;
        uint256 span = uint256(MAX_RATING - MIN_RATING) * SCALE;
        return ((avgScaled - floorScaled) * SCALE) / span;
    }

    function _onTimeRate(Record memory r) internal pure returns (uint256) {
        if (r.completed == 0) return NEUTRAL;
        return (uint256(r.onTime) * SCALE) / r.completed;
    }

    /**
     * @dev A courier with no disputes has nothing held against them, so this
     *      component starts full rather than neutral. Never having been disputed
     *      is not the same as lacking evidence — it is the evidence.
     */
    function _disputeRate(Record memory r) internal pure returns (uint256) {
        uint256 total = uint256(r.disputesWon) + r.disputesLost;
        if (total == 0) return SCALE;
        return (uint256(r.disputesWon) * SCALE) / total;
    }

    /// @dev Same reasoning: no assignments means nothing abandoned.
    function _cancellationRate(Record memory r) internal pure returns (uint256) {
        if (r.assignments == 0) return SCALE;
        uint256 cancelled = r.cancelledByCourier;
        if (cancelled >= r.assignments) return 0;
        return SCALE - ((cancelled * SCALE) / r.assignments);
    }

    /// @dev Saturating: past FULL_CONFIDENCE_AT completions, more adds nothing.
    function _experienceRate(Record memory r) internal pure returns (uint256) {
        if (r.completed >= FULL_CONFIDENCE_AT) return SCALE;
        return (uint256(r.completed) * SCALE) / FULL_CONFIDENCE_AT;
    }

    function _emitUpdate(address courier) internal {
        emit ReputationUpdated(courier, scoreOf(courier), confidenceOf(courier), ALGORITHM_VERSION);
    }
}
