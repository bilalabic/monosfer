// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title ISettlementVault
 * @notice Custody and settlement surface that the delivery lifecycle depends on.
 * @dev Baseline ref sec. 32.12: the lifecycle must not permanently depend on a single
 *      production payment rail. That abstraction lives here. V1 ships one
 *      implementation settling in native MON; a future rail is a different
 *      implementation of this same interface, not a change to the hub.
 *
 *      The interface is deliberately push-free. Nothing here sends value to a
 *      third party: settlement only ever moves an internal balance from "locked"
 *      to "claimable", and value leaves solely when the owner pulls it. That is
 *      what makes a reverting receiver unable to block anyone else's settlement
 *      (sec. 18.2, invariant sec. 33-11).
 */
interface ISettlementVault {
    /// @notice One leg of a settlement: `amount` becomes claimable by `to`.
    struct Payout {
        address to;
        uint256 amount;
    }

    /// @notice Take custody of `msg.value` under `lockId`, owned by `owner`.
    function lock(bytes32 lockId, address owner) external payable;

    /// @notice Add value to an existing active lock.
    function topUpLock(bytes32 lockId) external payable;

    /// @notice Split a lock into claimable balances. Payout total must equal the lock exactly.
    function releaseLock(bytes32 lockId, Payout[] calldata payouts) external;

    /**
     * @notice Credit part of a lock, leaving the remainder locked and active.
     * @dev Needed by stake accounting, where a holder withdraws part of a balance
     *      that must otherwise stay under custody. Delivery settlement uses
     *      `releaseLock` instead, whose exact-total rule is a safety property.
     */
    function releasePartial(bytes32 lockId, Payout[] calldata payouts) external;

    /// @notice Return a lock in full to its owner's claimable balance.
    function refundLock(bytes32 lockId) external;

    /// @notice Withdraw the caller's own claimable balance.
    function claim() external returns (uint256 amount);

    /// @notice Withdraw `account`'s claimable balance to `account`. Callable by anyone.
    function claimFor(address account) external returns (uint256 amount);

    function claimableOf(address account) external view returns (uint256);
    function lockAmount(bytes32 lockId) external view returns (uint256);
    function lockOwner(bytes32 lockId) external view returns (address);
    function totalLiabilities() external view returns (uint256);

    event Locked(bytes32 indexed lockId, address indexed owner, uint256 amount);
    event LockToppedUp(bytes32 indexed lockId, uint256 amount, uint256 newTotal);
    event LockReleased(bytes32 indexed lockId, uint256 amount);
    event LockPartiallyReleased(bytes32 indexed lockId, uint256 amount, uint256 remaining);
    event LockRefunded(bytes32 indexed lockId, address indexed owner, uint256 amount);
    event Credited(address indexed account, uint256 amount, bytes32 indexed lockId);
    event Claimed(address indexed account, uint256 amount);
}
