// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title ProtocolAccessManager
 * @notice Central role and emergency-pause authority for the MONOSFER V1 contracts.
 * @dev Baseline refs: sec. 32.11 (no single EOA controls critical permissions),
 *      sec. 45 (multisig for critical control, delayed privileged configuration,
 *      emergency pause), invariant sec. 33-15 (admin actions stay inside bounds).
 *
 *      Built on OpenZeppelin `AccessControlDefaultAdminRules`, which supplies
 *      two-step, delayed transfer of the default admin and guarantees there is
 *      exactly one default admin at a time. OpenZeppelin's own `AccessManager`
 *      was considered and not used: it is a heavier per-function scheduling
 *      system than four protocol roles require, and a smaller explicit surface
 *      is easier to review. This contract is named `ProtocolAccessManager` to
 *      avoid colliding with that OpenZeppelin contract.
 *
 *      Asymmetric pause timing is deliberate. Pausing protects users, so it is
 *      immediate. Unpausing removes that protection, so it must be scheduled
 *      and waited out, which prevents a single compromised key from flipping
 *      protection off the moment it is turned on.
 */
contract ProtocolAccessManager is AccessControlDefaultAdminRules {
    /// @notice May propose and execute protocol configuration changes.
    bytes32 public constant CONFIG_ADMIN_ROLE = keccak256("MONOSFER_CONFIG_ADMIN_ROLE");

    /// @notice May pause the protocol immediately. Cannot unpause.
    bytes32 public constant EMERGENCY_ROLE = keccak256("MONOSFER_EMERGENCY_ROLE");

    /// @notice May rotate the off-chain attestation signers.
    bytes32 public constant SIGNER_ADMIN_ROLE = keccak256("MONOSFER_SIGNER_ADMIN_ROLE");

    /// @notice May perform treasury operations.
    bytes32 public constant TREASURER_ROLE = keccak256("MONOSFER_TREASURER_ROLE");

    /// @notice Protocol contracts allowed to lock and settle funds in SettlementVault.
    /// @dev Held by contracts (DeliveryHub, DisputeCourt), never by an EOA.
    bytes32 public constant VAULT_CONTROLLER_ROLE = keccak256("MONOSFER_VAULT_CONTROLLER_ROLE");

    /// @notice Protocol contracts allowed to move courier collateral and custody counters.
    /// @dev Held by contracts (DeliveryHub, DisputeCourt), never by an EOA.
    bytes32 public constant REGISTRY_CONTROLLER_ROLE = keccak256("MONOSFER_REGISTRY_CONTROLLER_ROLE");

    /// @notice May set courier verification levels and suspend couriers.
    /// @dev Reflects an off-chain verification decision on-chain (sec.4.4, sec.4.5).
    bytes32 public constant VERIFIER_ROLE = keccak256("MONOSFER_VERIFIER_ROLE");

    /// @notice May write courier reputation. Held by protocol contracts only:
    ///         an account that can write reputation can manufacture standing.
    bytes32 public constant REPUTATION_REPORTER_ROLE = keccak256("MONOSFER_REPUTATION_REPORTER_ROLE");

    /// @notice May award the one badge the chain cannot verify for itself —
    ///         the weekly ranking, which sec. 22 keeps in an indexer. Narrow by
    ///         design: it cannot mint the history-based badges.
    bytes32 public constant BADGE_AWARDER_ROLE = keccak256("MONOSFER_BADGE_AWARDER_ROLE");

    /// @notice May seat, release and slash jurors. Held by `DisputeCourt` alone;
    ///         an EOA with this role could take a juror's stake at will.
    bytes32 public constant DISPUTE_COURT_ROLE = keccak256("MONOSFER_DISPUTE_COURT_ROLE");

    /**
     * @notice Held by the contracts that witness a wallet qualifying for a
     *         referral reward (sec. 25).
     * @dev Separate from `REPUTATION_REPORTER_ROLE` even though the same
     *      contracts hold both today. They authorise different things — one
     *      writes a score, the other commits money out of the referral purse —
     *      and a single role would mean revoking either revokes both.
     */
    bytes32 public constant REFERRAL_REPORTER_ROLE = keccak256("MONOSFER_REFERRAL_REPORTER_ROLE");

    /// @notice Delay between scheduling an unpause and being able to execute it.
    uint256 public constant UNPAUSE_DELAY = 6 hours;

    /// @notice Minimum delay for a default-admin handover, enforced at construction.
    uint48 public constant MIN_ADMIN_TRANSFER_DELAY = 1 days;

    bool private _paused;
    uint64 private _unpauseReadyAt;

    event ProtocolPaused(address indexed account);
    event UnpauseScheduled(address indexed account, uint64 readyAt);
    event ProtocolUnpaused(address indexed account);

    error EnforcedPause();
    error ExpectedPause();
    error AlreadyPaused();
    error UnpauseNotScheduled();
    error UnpauseTooEarly(uint64 readyAt);
    error AdminTransferDelayTooShort(uint48 provided, uint48 minimum);
    error ZeroAddress();

    /**
     * @param adminTransferDelay Delay for handing over the default admin role.
     * @param initialAdmin Holder of the default admin role at deployment.
     */
    constructor(uint48 adminTransferDelay, address initialAdmin)
        AccessControlDefaultAdminRules(adminTransferDelay, initialAdmin)
    {
        if (initialAdmin == address(0)) revert ZeroAddress();
        if (adminTransferDelay < MIN_ADMIN_TRANSFER_DELAY) {
            revert AdminTransferDelayTooShort(adminTransferDelay, MIN_ADMIN_TRANSFER_DELAY);
        }
    }

    // --------------------------------------------------------------------
    // Pause
    // --------------------------------------------------------------------

    /// @notice True while the protocol is paused.
    function paused() external view returns (bool) {
        return _paused;
    }

    /// @notice Timestamp from which `unpause` may be executed, or 0 if unscheduled.
    function unpauseReadyAt() external view returns (uint64) {
        return _unpauseReadyAt;
    }

    /**
     * @notice Pause the protocol immediately.
     * @dev Also clears any scheduled unpause, so a pause always restarts the
     *      full waiting period rather than inheriting an in-flight schedule.
     */
    function pause() external onlyRole(EMERGENCY_ROLE) {
        if (_paused) revert AlreadyPaused();
        _paused = true;
        _unpauseReadyAt = 0;
        emit ProtocolPaused(msg.sender);
    }

    /// @notice Begin the waiting period before the protocol can be unpaused.
    function scheduleUnpause() external onlyRole(CONFIG_ADMIN_ROLE) {
        if (!_paused) revert ExpectedPause();
        uint64 readyAt = SafeCast.toUint64(block.timestamp + UNPAUSE_DELAY);
        _unpauseReadyAt = readyAt;
        emit UnpauseScheduled(msg.sender, readyAt);
    }

    /// @notice Unpause the protocol once the scheduled delay has elapsed.
    function unpause() external onlyRole(CONFIG_ADMIN_ROLE) {
        if (!_paused) revert ExpectedPause();
        uint64 readyAt = _unpauseReadyAt;
        if (readyAt == 0) revert UnpauseNotScheduled();
        if (block.timestamp < readyAt) revert UnpauseTooEarly(readyAt);
        _paused = false;
        _unpauseReadyAt = 0;
        emit ProtocolUnpaused(msg.sender);
    }

    // --------------------------------------------------------------------
    // Guards for consumer contracts
    // --------------------------------------------------------------------

    /// @notice Reverts unless `account` holds `role`.
    function requireRole(bytes32 role, address account) external view {
        _checkRole(role, account);
    }

    /// @notice Reverts while the protocol is paused.
    function requireNotPaused() external view {
        if (_paused) revert EnforcedPause();
    }
}
