// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {ProtocolAccessManager} from "../access/ProtocolAccessManager.sol";
import {ISettlementVault} from "../interfaces/ISettlementVault.sol";

/**
 * @title SettlementVault
 * @notice Native-MON custody for the MONOSFER protocol.
 * @dev Baseline refs: sec. 32.2 (vault responsibilities and the solvency
 *      property), sec. 18.2 (pull-payment model), sec. 45 (reentrancy protection,
 *      CEI, safe user exits during pause), invariants sec. 33-1, sec. 33-3 and
 *      sec. 33-11.
 *
 *      ## Settlement is bookkeeping; only the owner moves value
 *
 *      `releaseLock` and `refundLock` make no external call. They move an
 *      internal balance from a lock into `claimable`, and that is all. Value
 *      leaves this contract in exactly one place — `_payOut` — reached only when
 *      an account pulls its own funds.
 *
 *      The property this buys: **no payee can affect any other payee.** A wallet
 *      that reverts on receive, burns all its gas, or simply never calls `claim`
 *      still gets credited, and everyone else settles and withdraws normally. A
 *      failed pull reverts that one caller's transaction and leaves their balance
 *      untouched, ready to be pulled again later.
 *
 *      ## Solvency
 *
 *      After every state-changing call:
 *
 *          address(this).balance >= totalLocked + totalClaimable
 *
 *      This is asserted in code rather than only in tests, because a violation
 *      means user funds are already gone. Balance may exceed liabilities — value
 *      force-sent via `selfdestruct` is unaccounted for and is reported by
 *      `surplus()` — but it may never fall below.
 *
 *      Payouts must sum to the lock exactly, not "at most". A short payout would
 *      leave a remainder with no owner, which is a slow leak rather than a loud
 *      failure (invariant sec. 33-3).
 *
 *      ## Pause
 *
 *      Taking new custody stops while paused. Releasing and refunding stay open,
 *      because they only move internal balances toward users, and `claim` is
 *      never blocked: a paused protocol must still be exitable (sec. 45).
 */
contract SettlementVault is ISettlementVault, ReentrancyGuard {
    enum LockStatus {
        None,
        Active,
        Settled
    }

    struct Lock {
        address owner;
        uint96 amount;
        LockStatus status;
    }

    /// @dev uint96 holds ~7.9e28 wei, far above any plausible single delivery.
    uint256 private constant MAX_LOCK_AMOUNT = type(uint96).max;

    ProtocolAccessManager public immutable accessManager;

    mapping(bytes32 => Lock) private _locks;
    mapping(address => uint256) private _claimable;

    uint256 public totalLocked;
    uint256 public totalClaimable;

    error ZeroAddress();
    error ZeroAmount();
    error LockAlreadyExists(bytes32 lockId);
    error LockNotActive(bytes32 lockId);
    error LockAmountTooLarge(uint256 amount);
    error PayoutMismatch(uint256 expected, uint256 provided);
    error NoPayouts();
    error NothingToClaim(address account);
    error ClaimTransferFailed(address account, uint256 amount);
    error VaultInsolvent(uint256 balance, uint256 liabilities);

    modifier onlyController() {
        _checkController();
        _;
    }

    modifier whenNotPaused() {
        accessManager.requireNotPaused();
        _;
    }

    /**
     * @dev Every state-changing path ends here. Placing the check in a modifier
     *      rather than trusting each function keeps the property true by
     *      construction as the contract grows in later phases.
     */
    modifier solvent() {
        _;
        uint256 liabilities = totalLocked + totalClaimable;
        if (address(this).balance < liabilities) {
            revert VaultInsolvent(address(this).balance, liabilities);
        }
    }

    constructor(ProtocolAccessManager accessManager_) {
        if (address(accessManager_) == address(0)) revert ZeroAddress();
        accessManager = accessManager_;
    }

    function _checkController() internal view {
        accessManager.requireRole(accessManager.VAULT_CONTROLLER_ROLE(), msg.sender);
    }

    // --------------------------------------------------------------------
    // Custody in
    // --------------------------------------------------------------------

    /// @inheritdoc ISettlementVault
    function lock(bytes32 lockId, address owner) external payable onlyController whenNotPaused solvent {
        if (owner == address(0)) revert ZeroAddress();
        if (msg.value == 0) revert ZeroAmount();
        if (msg.value > MAX_LOCK_AMOUNT) revert LockAmountTooLarge(msg.value);
        if (_locks[lockId].status != LockStatus.None) revert LockAlreadyExists(lockId);

        _locks[lockId] = Lock({owner: owner, amount: uint96(msg.value), status: LockStatus.Active});
        totalLocked += msg.value;

        emit Locked(lockId, owner, msg.value);
    }

    /// @inheritdoc ISettlementVault
    function topUpLock(bytes32 lockId) external payable onlyController whenNotPaused solvent {
        if (msg.value == 0) revert ZeroAmount();

        Lock storage l = _locks[lockId];
        if (l.status != LockStatus.Active) revert LockNotActive(lockId);

        uint256 newTotal = uint256(l.amount) + msg.value;
        if (newTotal > MAX_LOCK_AMOUNT) revert LockAmountTooLarge(newTotal);

        l.amount = uint96(newTotal);
        totalLocked += msg.value;

        emit LockToppedUp(lockId, msg.value, newTotal);
    }

    // --------------------------------------------------------------------
    // Settlement — bookkeeping only, never an external call
    // --------------------------------------------------------------------

    /**
     * @inheritdoc ISettlementVault
     * @dev Payouts must sum to the lock exactly, not "at most" — see the
     *      contract note on why a remainder with no owner is unacceptable.
     */
    function releaseLock(bytes32 lockId, Payout[] calldata payouts) external onlyController solvent {
        Lock storage l = _locks[lockId];
        if (l.status != LockStatus.Active) revert LockNotActive(lockId);
        if (payouts.length == 0) revert NoPayouts();

        uint256 lockedAmount = l.amount;

        uint256 distributed = 0;
        for (uint256 i = 0; i < payouts.length; i++) {
            Payout calldata p = payouts[i];
            if (p.to == address(0)) revert ZeroAddress();
            if (p.amount == 0) revert ZeroAmount();
            distributed += p.amount;
        }
        if (distributed != lockedAmount) revert PayoutMismatch(lockedAmount, distributed);

        // Effects before any crediting, and there are no external calls at all.
        l.status = LockStatus.Settled;
        l.amount = 0;
        totalLocked -= lockedAmount;
        totalClaimable += lockedAmount;

        for (uint256 i = 0; i < payouts.length; i++) {
            _claimable[payouts[i].to] += payouts[i].amount;
            emit Credited(payouts[i].to, payouts[i].amount, lockId);
        }

        emit LockReleased(lockId, lockedAmount);
    }

    /**
     * @inheritdoc ISettlementVault
     * @dev Unlike `releaseLock`, the payout total may be less than the lock; the
     *      remainder stays locked and the lock stays active. That is exactly what
     *      a partial stake withdrawal needs. Paying out the whole remainder is
     *      allowed and settles the lock.
     */
    function releasePartial(bytes32 lockId, Payout[] calldata payouts) external onlyController solvent {
        Lock storage l = _locks[lockId];
        if (l.status != LockStatus.Active) revert LockNotActive(lockId);
        if (payouts.length == 0) revert NoPayouts();

        uint256 lockedAmount = l.amount;

        uint256 distributed = 0;
        for (uint256 i = 0; i < payouts.length; i++) {
            if (payouts[i].to == address(0)) revert ZeroAddress();
            if (payouts[i].amount == 0) revert ZeroAmount();
            distributed += payouts[i].amount;
        }
        if (distributed > lockedAmount) revert PayoutMismatch(lockedAmount, distributed);

        uint256 remaining = lockedAmount - distributed;
        l.amount = uint96(remaining);
        if (remaining == 0) l.status = LockStatus.Settled;
        totalLocked -= distributed;
        totalClaimable += distributed;

        for (uint256 i = 0; i < payouts.length; i++) {
            _claimable[payouts[i].to] += payouts[i].amount;
            emit Credited(payouts[i].to, payouts[i].amount, lockId);
        }

        emit LockPartiallyReleased(lockId, distributed, remaining);
    }

    /// @inheritdoc ISettlementVault
    function refundLock(bytes32 lockId) external onlyController solvent {
        Lock storage l = _locks[lockId];
        if (l.status != LockStatus.Active) revert LockNotActive(lockId);

        uint256 amount = l.amount;
        address owner = l.owner;

        l.status = LockStatus.Settled;
        l.amount = 0;
        totalLocked -= amount;
        totalClaimable += amount;
        _claimable[owner] += amount;

        emit Credited(owner, amount, lockId);
        emit LockRefunded(lockId, owner, amount);
    }

    // --------------------------------------------------------------------
    // Custody out — the only place value leaves this contract
    // --------------------------------------------------------------------

    /**
     * @inheritdoc ISettlementVault
     * @dev Deliberately callable while paused: sec. 45 requires users to be able to
     *      exit a paused protocol.
     */
    function claim() external nonReentrant solvent returns (uint256 amount) {
        return _payOut(msg.sender);
    }

    /**
     * @inheritdoc ISettlementVault
     * @dev Permissionless, but always pays `account` itself, never the caller.
     *      A keeper can therefore push funds to a user without being able to
     *      redirect them.
     */
    function claimFor(address account) external nonReentrant solvent returns (uint256 amount) {
        if (account == address(0)) revert ZeroAddress();
        return _payOut(account);
    }

    function _payOut(address account) internal returns (uint256 amount) {
        amount = _claimable[account];
        if (amount == 0) revert NothingToClaim(account);

        // Checks-effects-interactions: the balance is cleared before the call, and
        // nonReentrant blocks re-entry regardless.
        _claimable[account] = 0;
        totalClaimable -= amount;

        (bool ok,) = account.call{value: amount}("");
        // Reverting here rolls back this caller's transaction only, restoring the
        // balance. It cannot affect any other account's settlement, because no
        // other account's funds are touched by this call.
        if (!ok) revert ClaimTransferFailed(account, amount);

        emit Claimed(account, amount);
    }

    // --------------------------------------------------------------------
    // Views
    // --------------------------------------------------------------------

    function claimableOf(address account) external view returns (uint256) {
        return _claimable[account];
    }

    function lockAmount(bytes32 lockId) external view returns (uint256) {
        return _locks[lockId].amount;
    }

    function lockOwner(bytes32 lockId) external view returns (address) {
        return _locks[lockId].owner;
    }

    function lockStatus(bytes32 lockId) external view returns (LockStatus) {
        return _locks[lockId].status;
    }

    /// @inheritdoc ISettlementVault
    function totalLiabilities() external view returns (uint256) {
        return totalLocked + totalClaimable;
    }

    /// @notice Value held beyond recorded liabilities. Force-sent funds land here.
    function surplus() external view returns (uint256) {
        uint256 liabilities = totalLocked + totalClaimable;
        return address(this).balance > liabilities ? address(this).balance - liabilities : 0;
    }

    /**
     * @dev No plain `receive()`. Value only enters through `lock`/`topUpLock`,
     *      which record it. Untracked value can still be force-sent via
     *      `selfdestruct`, which is harmless: it raises the balance above
     *      liabilities and `surplus()` reports it.
     */
}
