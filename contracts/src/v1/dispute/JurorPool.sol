// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {ProtocolAccessManager} from "../access/ProtocolAccessManager.sol";
import {ProtocolConfig} from "../config/ProtocolConfig.sol";

/**
 * @title JurorPool
 * @notice Juror stake, eligibility and the frozen candidate set a draw runs over.
 * @dev Baseline refs: sec. 4.6 (juror standing is separate from courier standing),
 *      sec. 27 (10 MON minimum, 2 MON locked per case, 1 MON non-reveal slash,
 *      equal-weight selection), invariants sec. 33-13 and sec. 33-18.
 *
 *      ## Juror stake is not courier stake
 *
 *      A courier's collateral answers for a package; a juror's stake answers for
 *      showing up and voting honestly. sec. 4.6 keeps them apart, and so does
 *      this contract: it shares no storage with `CourierRegistry`, and being one
 *      confers nothing on the other.
 *
 *      ## Stake buys a seat at the table, not a louder voice
 *
 *      sec. 27 is explicit that stake above the minimum grants no extra weight.
 *      Eligibility is therefore a boolean, and selection draws uniformly from
 *      those who pass it. A juror with a thousand MON and one with ten are the
 *      same candidate here.
 *
 *      ## The candidate set is copied when a draw is requested
 *
 *      Invariant sec. 33-18 says membership changes must not be able to steer a
 *      draw that has already been requested. The simplest way to guarantee that
 *      is to stop the draw depending on live membership at all: the eligible
 *      addresses are copied into the draw when randomness is requested, and the
 *      selection later reads only that copy.
 *
 *      The alternatives were worse. Invalidating a pending draw whenever anyone
 *      leaves hands any single juror a way to stall every dispute. Freezing the
 *      pool while a draw is open couples unrelated disputes to each other and
 *      traps people's money. Copying costs gas and nothing else, and the cost
 *      falls on the party that opened the dispute, alongside the arbitration fee
 *      they already pay.
 *
 *      The copy is bounded by `MAX_SNAPSHOT`, which is what makes that cost
 *      predictable. It is a real ceiling on the testnet pool and the scaling path
 *      — a sortition tree, where a snapshot is one root hash — is a later
 *      change, not a hidden assumption here.
 */
contract JurorPool is ReentrancyGuard {
    // --------------------------------------------------------------------
    // Constants
    // --------------------------------------------------------------------

    /**
     * @notice Largest candidate set a single draw will copy.
     * @dev Each entry is one storage write when a draw is requested. This bounds
     *      that cost; past it, the pool cannot grow until the ceiling is raised
     *      in a new deployment. Deliberately a constant rather than config: it is
     *      a statement about gas, not an economic parameter.
     */
    uint256 public constant MAX_SNAPSHOT = 128;

    // --------------------------------------------------------------------
    // Storage
    // --------------------------------------------------------------------

    /**
     * @param stake    Total MON the juror has placed.
     * @param locked   Portion committed to cases currently in flight.
     * @param active   Whether they are standing for selection.
     * @param cases    Cases they are currently seated on.
     */
    struct Juror {
        uint96 stake;
        uint96 locked;
        bool active;
        uint32 cases;
    }

    ProtocolAccessManager public immutable accessManager;
    ProtocolConfig public immutable config;

    mapping(address => Juror) internal _jurors;

    /// @notice Everyone currently standing for selection, in no meaningful order.
    address[] internal _eligible;
    mapping(address => uint256) internal _eligibleIndex;

    /// @notice Frozen candidate sets, one per draw (invariant sec. 33-18).
    // Written by `takeSnapshot` and by nothing else; an unwritten draw id reads
    // as an empty set, which is the correct answer for a draw that never
    // happened. Slither reports every mapping declaration this way.
    // slither-disable-next-line uninitialized-state
    mapping(uint256 => address[]) internal _snapshots;

    /**
     * @notice What a juror actually has locked against one draw.
     * @dev The amount is recorded at seat time rather than re-read from config
     *      when the seat is given up. `jurorLockPerCase` is a governable
     *      parameter, and a case outlives the transaction that opened it: if the
     *      parameter rises mid-case, re-reading it would release more than was
     *      ever locked and eat into another case's collateral; if it falls, the
     *      difference would stay locked with nothing left to release it.
     *
     *      `held` is a separate flag rather than `locked != 0` because a lock of
     *      zero is a legal configuration, and a seat still has to be
     *      distinguishable from an empty one.
     */
    struct Seat {
        bool held;
        uint96 locked;
    }

    mapping(uint256 => mapping(address => Seat)) internal _seats;

    /// @notice What `juror` has locked against `drawId`, and whether they hold a seat.
    function seatOf(uint256 drawId, address juror) external view returns (bool held, uint96 locked) {
        Seat storage seatRecord = _seats[drawId][juror];
        return (seatRecord.held, seatRecord.locked);
    }

    /// @notice MON taken from jurors who committed and never revealed.
    uint256 public slashedTotal;

    /// @notice MON owed to jurors but not yet withdrawn.
    uint256 public totalStaked;

    // --------------------------------------------------------------------
    // Events and errors
    // --------------------------------------------------------------------

    event JurorStaked(address indexed juror, uint256 amount, uint256 stake);
    event JurorWithdrew(address indexed juror, uint256 amount, uint256 stake);
    event JurorActivated(address indexed juror);
    event JurorDeactivated(address indexed juror);
    event SnapshotTaken(uint256 indexed drawId, uint256 candidates);
    event JurorSeated(uint256 indexed drawId, address indexed juror, uint256 locked);
    event JurorReleased(uint256 indexed drawId, address indexed juror, uint256 released);
    event JurorSlashed(uint256 indexed drawId, address indexed juror, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error BelowMinimumStake(uint256 stake, uint256 minimum);
    error NotActive(address juror);
    error AlreadyActive(address juror);
    error StakeLocked(uint256 requested, uint256 available);
    error PoolFull(uint256 max);
    error SnapshotEmpty(uint256 drawId);
    error SnapshotExists(uint256 drawId);
    error WithdrawFailed(address to, uint256 amount);
    error Insolvent();

    // --------------------------------------------------------------------
    // Wiring
    // --------------------------------------------------------------------

    constructor(ProtocolAccessManager accessManager_, ProtocolConfig config_) {
        if (address(accessManager_) == address(0)) revert ZeroAddress();
        if (address(config_) == address(0)) revert ZeroAddress();
        accessManager = accessManager_;
        config = config_;
    }

    /// @dev Seating, releasing and slashing belong to the court, never to an EOA.
    modifier onlyCourt() {
        accessManager.requireRole(accessManager.DISPUTE_COURT_ROLE(), msg.sender);
        _;
    }

    modifier solvent() {
        _;
        if (address(this).balance < totalStaked) revert Insolvent();
    }

    // --------------------------------------------------------------------
    // Standing
    // --------------------------------------------------------------------

    /// @notice Add to your stake. Does not by itself put you up for selection.
    function stake() external payable solvent {
        if (msg.value == 0) revert ZeroAmount();
        Juror storage j = _jurors[msg.sender];
        j.stake += uint96(msg.value);
        totalStaked += msg.value;
        emit JurorStaked(msg.sender, msg.value, j.stake);
    }

    /**
     * @notice Stand for selection.
     * @dev Separate from staking so a juror can top up without announcing
     *      availability, and can step back without withdrawing their money.
     */
    function activate() external {
        Juror storage j = _jurors[msg.sender];
        if (j.active) revert AlreadyActive(msg.sender);

        uint256 minimum = config.minJurorStake();
        if (j.stake < minimum) revert BelowMinimumStake(j.stake, minimum);
        if (_eligible.length >= MAX_SNAPSHOT) revert PoolFull(MAX_SNAPSHOT);

        j.active = true;
        _eligibleIndex[msg.sender] = _eligible.length;
        _eligible.push(msg.sender);
        emit JurorActivated(msg.sender);
    }

    /**
     * @notice Step back from selection.
     * @dev Allowed while seated on a case: leaving the candidate list does not
     *      abandon cases already accepted, and the stake backing them stays
     *      locked. A draw already requested is unaffected, because it reads its
     *      own frozen copy (sec. 33-18).
     */
    function deactivate() external {
        _deactivate(msg.sender);
    }

    /**
     * @dev Clears a seat and returns exactly what it was holding. Clearing lets a
     *      juror stand again on a later round of the same dispute, which appeals
     *      need; leaving it set would silently shrink every panel after the first.
     *      Releasing a seat that was never held is a no-op rather than a revert,
     *      so the court can sweep a panel without tracking which members it
     *      actually managed to seat.
     */
    function _giveUpSeat(uint256 drawId, address juror) internal returns (uint96 amount) {
        Seat storage seatRecord = _seats[drawId][juror];
        if (!seatRecord.held) return 0;

        amount = seatRecord.locked;
        delete _seats[drawId][juror];

        Juror storage j = _jurors[juror];
        // Defensive: the per-seat record is the source of truth, but a clamp
        // here means a corrupted pair can never underflow the aggregate.
        if (amount > j.locked) amount = j.locked;
        j.locked -= amount;
        if (j.cases > 0) j.cases -= 1;
    }

    function _deactivate(address juror) internal {
        Juror storage j = _jurors[juror];
        if (!j.active) revert NotActive(juror);

        j.active = false;
        uint256 i = _eligibleIndex[juror];
        uint256 last = _eligible.length - 1;
        if (i != last) {
            address moved = _eligible[last];
            _eligible[i] = moved;
            _eligibleIndex[moved] = i;
        }
        _eligible.pop();
        delete _eligibleIndex[juror];
        emit JurorDeactivated(juror);
    }

    /// @notice Withdraw unlocked stake. Locked stake belongs to open cases.
    function withdraw(uint256 amount) external nonReentrant solvent {
        if (amount == 0) revert ZeroAmount();
        Juror storage j = _jurors[msg.sender];

        uint256 free = uint256(j.stake) - j.locked;
        if (amount > free) revert StakeLocked(amount, free);

        j.stake -= uint96(amount);
        totalStaked -= amount;

        // Falling below the minimum takes you out of the pool rather than
        // leaving an ineligible name in it for a draw to pick.
        if (j.active && j.stake < config.minJurorStake()) _deactivate(msg.sender);

        emit JurorWithdrew(msg.sender, amount, j.stake);
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert WithdrawFailed(msg.sender, amount);
    }

    // --------------------------------------------------------------------
    // Draws
    // --------------------------------------------------------------------

    /**
     * @notice Freeze the current candidate set for `drawId` (invariant sec. 33-18).
     * @dev Called when randomness is requested, not when it arrives. Everything
     *      that happens to the pool afterwards is invisible to this draw.
     */
    function takeSnapshot(uint256 drawId) external onlyCourt returns (uint256 candidates) {
        if (_snapshots[drawId].length != 0) revert SnapshotExists(drawId);
        candidates = _eligible.length;
        if (candidates == 0) revert SnapshotEmpty(drawId);

        address[] storage snap = _snapshots[drawId];
        for (uint256 i = 0; i < candidates; i++) {
            snap.push(_eligible[i]);
        }
        emit SnapshotTaken(drawId, candidates);
    }

    function snapshotSize(uint256 drawId) external view returns (uint256) {
        return _snapshots[drawId].length;
    }

    function snapshotAt(uint256 drawId, uint256 index) external view returns (address) {
        return _snapshots[drawId][index];
    }

    /**
     * @notice Lock a juror's per-case stake when they take a seat.
     * @dev A juror whose free stake no longer covers the lock cannot be seated;
     *      the court skips them and draws the next candidate.
     */
    function seat(uint256 drawId, address juror) external onlyCourt returns (bool seated) {
        // One seat per juror per draw. The caller walks the snapshot and could
        // reach the same candidate twice; without this the second visit would
        // lock a second time and inflate the panel's weight by one silent vote.
        if (_seats[drawId][juror].held) return false;

        Juror storage j = _jurors[juror];
        uint256 lockPerCase = config.jurorLockPerCase();
        if (uint256(j.stake) - j.locked < lockPerCase) return false;

        j.locked += uint96(lockPerCase);
        j.cases += 1;
        _seats[drawId][juror] = Seat({held: true, locked: uint96(lockPerCase)});
        emit JurorSeated(drawId, juror, lockPerCase);
        return true;
    }

    /// @notice Release a seated juror's lock once the case is behind them.
    function release(uint256 drawId, address juror) external onlyCourt {
        uint96 amount = _giveUpSeat(drawId, juror);
        emit JurorReleased(drawId, juror, amount);
    }

    /**
     * @notice Take the non-reveal penalty from a juror, then release the rest.
     * @dev Invariant sec. 33-14: this is reachable only for failing to reveal.
     *      Nothing in this contract can slash a juror for how they voted, and the
     *      court has no other slashing entry point to call.
     */
    function slashForNonReveal(uint256 drawId, address juror) external onlyCourt {
        Juror storage j = _jurors[juror];
        uint256 penalty = config.nonRevealSlash();
        uint96 amount = j.stake < penalty ? j.stake : uint96(penalty);

        j.stake -= amount;
        totalStaked -= amount;
        slashedTotal += amount;

        _giveUpSeat(drawId, juror);

        // A slashed juror may now be below the minimum; if so they stop being a
        // candidate rather than lingering in the pool.
        if (j.active && j.stake < config.minJurorStake()) _deactivate(juror);

        emit JurorSlashed(drawId, juror, amount);
    }

    // --------------------------------------------------------------------
    // Reading
    // --------------------------------------------------------------------

    function jurorOf(address juror) external view returns (Juror memory) {
        return _jurors[juror];
    }

    function eligibleCount() external view returns (uint256) {
        return _eligible.length;
    }

    function eligibleAt(uint256 index) external view returns (address) {
        return _eligible[index];
    }

    /// @notice Whether `juror` would be drawn from today's pool.
    function isEligible(address juror) external view returns (bool) {
        Juror storage j = _jurors[juror];
        return j.active && j.stake >= config.minJurorStake();
    }

    /// @notice MON held beyond what is owed to jurors — slashed stake lives here.
    function surplus() external view returns (uint256) {
        uint256 balance = address(this).balance;
        return balance > totalStaked ? balance - totalStaked : 0;
    }
}
