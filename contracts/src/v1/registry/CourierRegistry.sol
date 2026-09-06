// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {ProtocolAccessManager} from "../access/ProtocolAccessManager.sol";
import {ProtocolConfig} from "../config/ProtocolConfig.sol";
import {ISettlementVault} from "../interfaces/ISettlementVault.sol";

/**
 * @title CourierRegistry
 * @notice Courier stake, verification level, suspension and physical custody.
 * @dev Baseline refs: sec. 32.3 (registry responsibilities), sec. 4.3–4.5 (C0/C1/C2),
 *      sec. 8.2 (base security deposit), sec. 8.3 (the same base collateral cannot
 *      protect two deliveries), sec. 9 (MAX_ACTIVE_CUSTODY), sec. 48 (24h withdrawal
 *      cooldown), invariants sec. 33-4 and sec. 33-10.
 *
 *      ## Every courier can always leave
 *
 *      Legacy `Delivera` has no `withdrawStake` at all, so staked MON is
 *      unrecoverable; `DeliveryEscrow` sets `isRegisteredCourier` once and never
 *      clears it, so a courier sitting at the minimum can never withdraw
 *      anything. Both were reproduced on a live chain.
 *
 *      Here a courier with no reserved collateral and no package in hand can
 *      always request their whole stake, wait out the cooldown, and take it.
 *      `deregister` exists as an explicit full exit, and registration status is
 *      derived from stake rather than being a one-way flag.
 *
 *      ## Funds live in the vault, not here
 *
 *      This contract holds no value. Stake is custodied by SettlementVault under
 *      one lock per courier, so there is a single solvency invariant for the
 *      whole protocol instead of one per contract (sec. 32.2).
 *
 *      ## Three-way split of a courier's stake
 *
 *          stake = available + reserved + pendingWithdrawal
 *
 *      Only `available` can back a new delivery or a new withdrawal request.
 *      `reserved` is committed to deliveries in flight; `pendingWithdrawal` is
 *      earmarked and in cooldown. Keeping the withdrawal earmark separate is
 *      what stops a courier from requesting an exit and then using the same MON
 *      as collateral while it waits (sec. 8.3).
 */
contract CourierRegistry is ReentrancyGuard {
    /// @notice sec. 4.3–4.5. `None` means not an active courier.
    enum VerificationLevel {
        None,
        C0,
        C1,
        C2
    }

    struct Courier {
        VerificationLevel level;
        bool suspended;
        uint96 stake;
        uint96 reserved;
        uint96 pendingWithdrawal;
        uint32 activeCustody;
        uint32 qualifiedDeliveries;
        uint64 withdrawalReadyAt;
    }

    ProtocolAccessManager public immutable accessManager;
    ProtocolConfig public immutable config;
    ISettlementVault public immutable vault;

    mapping(address => Courier) private _couriers;

    uint256 public totalStaked;
    uint256 public totalReserved;

    event StakeDeposited(address indexed courier, uint256 amount, uint256 newStake);
    event WithdrawalRequested(address indexed courier, uint256 amount, uint64 readyAt);
    event WithdrawalCancelled(address indexed courier, uint256 amount);
    event WithdrawalExecuted(address indexed courier, uint256 amount, uint256 newStake);
    event Deregistered(address indexed courier, uint256 amount);
    event CollateralReserved(address indexed courier, uint256 amount, uint256 totalReservedForCourier);
    event CollateralReleased(address indexed courier, uint256 amount);
    event CollateralSlashed(address indexed courier, uint256 amount, address indexed beneficiary);
    event CustodyOpened(address indexed courier, uint32 activeCustody);
    event CustodyClosed(address indexed courier, uint32 activeCustody);
    event QualifiedDeliveryRecorded(address indexed courier, uint32 total);
    event VerificationLevelSet(address indexed courier, VerificationLevel level);
    event SuspensionSet(address indexed courier, bool suspended);

    error ZeroAddress();
    error ZeroAmount();
    error NotActiveCourier(address courier);
    error StakeBelowMinimum(uint256 stake, uint256 minimum);
    error InsufficientAvailableStake(uint256 requested, uint256 available);
    error WithdrawalAlreadyPending(address courier);
    error NoPendingWithdrawal(address courier);
    error CooldownNotElapsed(uint64 readyAt);
    error HasReservedCollateral(uint256 reserved);
    error HasActiveCustody(uint32 activeCustody);
    error CustodyLimitReached(uint32 limit);
    error NoActiveCustody(address courier);
    error CourierSuspended(address courier);
    error AmountTooLarge(uint256 amount);

    modifier onlyRegistryController() {
        _checkRegistryController();
        _;
    }

    modifier onlyVerifier() {
        _checkVerifier();
        _;
    }

    modifier whenNotPaused() {
        accessManager.requireNotPaused();
        _;
    }

    function _checkRegistryController() internal view {
        accessManager.requireRole(accessManager.REGISTRY_CONTROLLER_ROLE(), msg.sender);
    }

    function _checkVerifier() internal view {
        accessManager.requireRole(accessManager.VERIFIER_ROLE(), msg.sender);
    }

    constructor(ProtocolAccessManager accessManager_, ProtocolConfig config_, ISettlementVault vault_) {
        if (address(accessManager_) == address(0)) revert ZeroAddress();
        if (address(config_) == address(0)) revert ZeroAddress();
        if (address(vault_) == address(0)) revert ZeroAddress();
        accessManager = accessManager_;
        config = config_;
        vault = vault_;
    }

    /**
     * @notice Deterministic vault lock id holding this courier's stake.
     * @dev The registry address is part of the id. Under the immutable-and-
     *      redeploy strategy a replacement registry shares the vault with the old
     *      one; without this, both would derive the same id for a courier and the
     *      new registry could never open a lock, because the vault rejects
     *      duplicate ids.
     */
    function stakeLockId(address courier) public view returns (bytes32) {
        return keccak256(abi.encodePacked("MONOSFER_COURIER_STAKE", address(this), courier));
    }

    // --------------------------------------------------------------------
    // Stake in
    // --------------------------------------------------------------------

    /**
     * @notice Stake MON to become, or stay, an active courier.
     * @dev Reaching the configured base deposit promotes an unregistered wallet
     *      to C0 (sec. 4.3). Higher levels are set by the verifier, never by staking.
     */
    function depositStake() external payable nonReentrant whenNotPaused {
        _deposit(msg.sender, msg.value);
    }

    /**
     * @notice Stake on behalf of `courier`, paid by the caller.
     * @dev Lets DeliveryHub take a courier's top-up and their coverage
     *      reservation in one transaction (sec. 8.3 additional bond). Restricted to
     *      protocol contracts, so nobody can inflate a stranger's stake.
     */
    function depositStakeFor(address courier) external payable nonReentrant whenNotPaused onlyRegistryController {
        if (courier == address(0)) revert ZeroAddress();
        _deposit(courier, msg.value);
    }

    function _deposit(address courier, uint256 amount) internal {
        if (amount == 0) revert ZeroAmount();

        Courier storage c = _couriers[courier];
        uint256 newStake = uint256(c.stake) + amount;
        if (newStake > type(uint96).max) revert AmountTooLarge(newStake);

        bytes32 lockId = stakeLockId(courier);
        bool isFirstLock = vault.lockAmount(lockId) == 0;

        // Effects before the interaction. The vault call reverts the whole
        // transaction if it fails, so recording first is safe and keeps CEI.
        c.stake = SafeCast.toUint96(newStake);
        totalStaked += amount;

        if (c.level == VerificationLevel.None && newStake >= config.courierBaseDeposit()) {
            c.level = VerificationLevel.C0;
            emit VerificationLevelSet(courier, VerificationLevel.C0);
        }
        emit StakeDeposited(courier, amount, newStake);

        if (isFirstLock) {
            vault.lock{value: amount}(lockId, courier);
        } else {
            vault.topUpLock{value: amount}(lockId);
        }
    }

    // --------------------------------------------------------------------
    // Stake out — always reachable
    // --------------------------------------------------------------------

    /**
     * @notice Begin the cooldown before withdrawing part of the stake.
     * @dev The amount is earmarked immediately so it cannot also back a delivery
     *      while it waits. Deliberately callable while paused: a courier must be
     *      able to start leaving a paused protocol (sec. 45).
     */
    function requestWithdrawal(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        Courier storage c = _couriers[msg.sender];
        if (c.withdrawalReadyAt != 0) revert WithdrawalAlreadyPending(msg.sender);

        uint256 available = _availableOf(c);
        if (amount > available) revert InsufficientAvailableStake(amount, available);

        c.pendingWithdrawal = SafeCast.toUint96(amount);
        uint64 readyAt = SafeCast.toUint64(block.timestamp) + config.courierWithdrawalCooldown();
        c.withdrawalReadyAt = readyAt;

        emit WithdrawalRequested(msg.sender, amount, readyAt);
    }

    /// @notice Abandon a pending withdrawal and return the amount to available stake.
    function cancelWithdrawal() external nonReentrant {
        Courier storage c = _couriers[msg.sender];
        if (c.withdrawalReadyAt == 0) revert NoPendingWithdrawal(msg.sender);

        uint256 amount = c.pendingWithdrawal;
        c.pendingWithdrawal = 0;
        c.withdrawalReadyAt = 0;

        emit WithdrawalCancelled(msg.sender, amount);
    }

    /**
     * @notice Complete a withdrawal once the cooldown has elapsed.
     * @dev Credits the vault's claimable balance rather than sending value, so a
     *      courier whose wallet rejects MON cannot brick anything. Also callable
     *      while paused, for the same reason as `requestWithdrawal`.
     */
    function executeWithdrawal() external nonReentrant returns (uint256 amount) {
        Courier storage c = _couriers[msg.sender];
        if (c.withdrawalReadyAt == 0) revert NoPendingWithdrawal(msg.sender);
        if (block.timestamp < c.withdrawalReadyAt) revert CooldownNotElapsed(c.withdrawalReadyAt);

        amount = c.pendingWithdrawal;
        c.pendingWithdrawal = 0;
        c.withdrawalReadyAt = 0;
        c.stake = SafeCast.toUint96(uint256(c.stake) - amount);
        totalStaked -= amount;

        // Falling below the base deposit drops the courier back to unregistered.
        // Registration is derived from stake, never a one-way flag.
        if (c.stake < config.courierBaseDeposit() && c.level != VerificationLevel.None) {
            c.level = VerificationLevel.None;
            emit VerificationLevelSet(msg.sender, VerificationLevel.None);
        }

        emit WithdrawalExecuted(msg.sender, amount, c.stake);

        ISettlementVault.Payout[] memory payouts = new ISettlementVault.Payout[](1);
        payouts[0] = ISettlementVault.Payout({to: msg.sender, amount: amount});
        vault.releasePartial(stakeLockId(msg.sender), payouts);
    }

    /**
     * @notice Request withdrawal of the entire stake and leave the courier role.
     * @dev The explicit full-exit path. Requires nothing reserved and nothing in
     *      hand, which is the only honest precondition: a courier holding a
     *      package or backing a delivery cannot walk away from it.
     */
    function deregister() external nonReentrant {
        Courier storage c = _couriers[msg.sender];
        if (c.stake == 0) revert NotActiveCourier(msg.sender);
        if (c.reserved != 0) revert HasReservedCollateral(c.reserved);
        if (c.activeCustody != 0) revert HasActiveCustody(c.activeCustody);
        if (c.withdrawalReadyAt != 0) revert WithdrawalAlreadyPending(msg.sender);

        uint256 amount = c.stake;
        c.pendingWithdrawal = SafeCast.toUint96(amount);
        uint64 readyAt = SafeCast.toUint64(block.timestamp) + config.courierWithdrawalCooldown();
        c.withdrawalReadyAt = readyAt;

        emit WithdrawalRequested(msg.sender, amount, readyAt);
        emit Deregistered(msg.sender, amount);
    }

    // --------------------------------------------------------------------
    // Collateral — controller only
    // --------------------------------------------------------------------

    /**
     * @notice Commit part of a courier's stake to a delivery.
     * @dev Invariant sec. 33-4: reservations are additive and bounded by available
     *      stake, so the same MON can never back two deliveries at once.
     */
    function reserveCollateral(address courier, uint256 amount) external onlyRegistryController {
        if (amount == 0) revert ZeroAmount();
        Courier storage c = _couriers[courier];
        if (c.level == VerificationLevel.None) revert NotActiveCourier(courier);
        if (c.suspended) revert CourierSuspended(courier);

        uint256 available = _availableOf(c);
        if (amount > available) revert InsufficientAvailableStake(amount, available);

        c.reserved = SafeCast.toUint96(uint256(c.reserved) + amount);
        totalReserved += amount;

        emit CollateralReserved(courier, amount, c.reserved);
    }

    /// @notice Release committed collateral back to available stake.
    function releaseCollateral(address courier, uint256 amount) external onlyRegistryController {
        if (amount == 0) revert ZeroAmount();
        Courier storage c = _couriers[courier];
        if (amount > c.reserved) revert InsufficientAvailableStake(amount, c.reserved);

        c.reserved = SafeCast.toUint96(uint256(c.reserved) - amount);
        totalReserved -= amount;

        emit CollateralReleased(courier, amount);
    }

    /**
     * @notice Move reserved collateral to a beneficiary's claimable balance.
     * @dev Slashing reduces stake as well as the reservation; the value leaves
     *      the courier's lock and becomes the beneficiary's to pull.
     */
    function slashCollateral(address courier, uint256 amount, address beneficiary)
        external
        nonReentrant
        onlyRegistryController
    {
        if (amount == 0) revert ZeroAmount();
        if (beneficiary == address(0)) revert ZeroAddress();
        Courier storage c = _couriers[courier];
        if (amount > c.reserved) revert InsufficientAvailableStake(amount, c.reserved);

        c.reserved = SafeCast.toUint96(uint256(c.reserved) - amount);
        c.stake = SafeCast.toUint96(uint256(c.stake) - amount);
        totalReserved -= amount;
        totalStaked -= amount;

        if (c.stake < config.courierBaseDeposit() && c.level != VerificationLevel.None) {
            c.level = VerificationLevel.None;
            emit VerificationLevelSet(courier, VerificationLevel.None);
        }

        emit CollateralSlashed(courier, amount, beneficiary);

        ISettlementVault.Payout[] memory payouts = new ISettlementVault.Payout[](1);
        payouts[0] = ISettlementVault.Payout({to: beneficiary, amount: amount});
        vault.releasePartial(stakeLockId(courier), payouts);
    }

    // --------------------------------------------------------------------
    // Physical custody — controller only
    // --------------------------------------------------------------------

    /// @dev Invariant sec. 33-10: a courier may hold at most `maxActiveCustody` packages.
    function openCustody(address courier) external onlyRegistryController {
        Courier storage c = _couriers[courier];
        if (c.level == VerificationLevel.None) revert NotActiveCourier(courier);
        if (c.suspended) revert CourierSuspended(courier);

        uint32 limit = config.maxActiveCustody();
        if (c.activeCustody >= limit) revert CustodyLimitReached(limit);

        c.activeCustody += 1;
        emit CustodyOpened(courier, c.activeCustody);
    }

    function closeCustody(address courier) external onlyRegistryController {
        Courier storage c = _couriers[courier];
        if (c.activeCustody == 0) revert NoActiveCustody(courier);
        c.activeCustody -= 1;
        emit CustodyClosed(courier, c.activeCustody);
    }

    function recordQualifiedDelivery(address courier) external onlyRegistryController {
        Courier storage c = _couriers[courier];
        c.qualifiedDeliveries += 1;
        emit QualifiedDeliveryRecorded(courier, c.qualifiedDeliveries);
    }

    // --------------------------------------------------------------------
    // Verification and suspension — verifier only
    // --------------------------------------------------------------------

    /**
     * @notice Record an off-chain verification decision (sec. 4.4, sec. 4.5).
     * @dev Promotion above C0 still requires the base deposit to be in place, so
     *      a verification badge can never stand in for collateral (sec. 24, sec. 3.3).
     */
    function setVerificationLevel(address courier, VerificationLevel level) external onlyVerifier {
        if (courier == address(0)) revert ZeroAddress();
        Courier storage c = _couriers[courier];

        if (level != VerificationLevel.None) {
            uint256 minimum = config.courierBaseDeposit();
            if (c.stake < minimum) revert StakeBelowMinimum(c.stake, minimum);
        }

        c.level = level;
        emit VerificationLevelSet(courier, level);
    }

    function setSuspended(address courier, bool suspended) external onlyVerifier {
        if (courier == address(0)) revert ZeroAddress();
        _couriers[courier].suspended = suspended;
        emit SuspensionSet(courier, suspended);
    }

    // --------------------------------------------------------------------
    // Views
    // --------------------------------------------------------------------

    function courierOf(address courier) external view returns (Courier memory) {
        return _couriers[courier];
    }

    function availableStake(address courier) external view returns (uint256) {
        return _availableOf(_couriers[courier]);
    }

    function _availableOf(Courier storage c) internal view returns (uint256) {
        return uint256(c.stake) - c.reserved - c.pendingWithdrawal;
    }

    /**
     * @notice Whether a courier may currently bid on a delivery of `riskTier`.
     * @dev sec. 6: R1 needs C0+, R2 needs C1+, R3 needs C2. R4 is disabled (sec. 49).
     */
    function isEligibleFor(address courier, uint8 riskTier) external view returns (bool) {
        Courier storage c = _couriers[courier];
        if (c.suspended || c.level == VerificationLevel.None) return false;
        if (c.stake < config.courierBaseDeposit()) return false;
        if (c.activeCustody >= config.maxActiveCustody()) return false;

        if (riskTier == 1) return true;
        if (riskTier == 2) return c.level >= VerificationLevel.C1;
        if (riskTier == 3) return c.level == VerificationLevel.C2;
        return false;
    }
}
