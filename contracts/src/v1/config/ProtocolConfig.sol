// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {ProtocolAccessManager} from "../access/ProtocolAccessManager.sol";

/**
 * @title ProtocolConfig
 * @notice Bounded, versioned, timelocked configuration for the MONOSFER V1 protocol.
 * @dev Baseline refs: sec. 32.1 (configuration must be bounded and versioned),
 *      sec. 48 (initial testnet parameters), sec. 45 (delayed privileged configuration),
 *      sec. 34 (configuration events), invariant sec. 33-15 (admin actions stay in bounds).
 *
 *      Every numeric parameter has hard MIN/MAX constants. No role, and no
 *      sequence of calls, can move a parameter outside its band: validation runs
 *      on execution, not only on proposal, so a bound can never be bypassed by a
 *      proposal made before some other change.
 *
 *      Parameters change as one atomic set rather than through ~20 individual
 *      setters. That keeps cross-field invariants (coverage ordering, jury size
 *      ordering, juror slash <= lock <= stake) checkable at every write, which
 *      per-field setters cannot guarantee.
 *
 *      Timing is deliberately asymmetric, mirroring ProtocolAccessManager:
 *      - numeric params and treasury/adapter addresses are timelocked, because
 *        changing them moves user money and should be observable in advance;
 *      - attestation signers rotate immediately, because the reason to rotate is
 *        usually that a key is compromised and forging quotes or delivery proofs.
 *        Waiting out a timelock there would extend the exposure window. The
 *        mitigation is that SIGNER_ADMIN_ROLE must be held by a multisig.
 */
contract ProtocolConfig {
    // --------------------------------------------------------------------
    // Types
    // --------------------------------------------------------------------

    struct Params {
        // --- economics ---
        uint16 protocolFeeBps; // sec. 48: 2% = 200
        uint16 coverageBpsR1; // sec. 6: 25% = 2500
        uint16 coverageBpsR2; // sec. 6: 60% = 6000
        uint16 coverageBpsR3; // sec. 6: 100% = 10000
        // Bounds on the reputation multiplier the off-chain risk service may
        // apply to the tier baseline (sec. 8.3). Enforced on-chain so a
        // compromised quote signer cannot price coverage at zero.
        uint16 coverageMultiplierMinBps; // 0.75x
        uint16 coverageMultiplierMaxBps; // 1.5x
        // --- limits ---
        uint8 maxActiveCustody; // sec. 9: 1
        uint8 customerMaxActiveListings; // sec. 48: 5
        uint8 juryFirstSize; // sec. 48: 3
        uint8 juryAppeal1Size; // sec. 48: 5
        uint8 juryAppeal2Size; // sec. 48: 7
        // --- windows (seconds) ---
        uint32 biddingWindow; // beyond sec. 48 — see note below
        uint32 fundingWindow; // sec. 48: 15 min
        uint32 pickupWindow; // beyond sec. 48
        uint32 transitWindow; // beyond sec. 48
        uint32 returnWindow; // beyond sec. 48
        uint32 ratingWindow; // beyond sec. 48 — sec. 20 requires a bound, not a figure
        uint32 challengeWindow; // sec. 48: 24 h
        uint32 courierWithdrawalCooldown; // sec. 48: 24 h
        uint32 riskQuoteValidity; // sec. 48: 5 min
        uint32 podAttestationValidity; // sec. 48: 10 min
        uint32 rewardClaimWindow; // sec. 48: 90 days
        uint32 rewardReclaimDelay; // sec. 48: 7 days
        // --- stakes (wei) ---
        uint128 courierBaseDeposit; // sec. 48: 10 MON
        uint128 minJurorStake; // sec. 48: 10 MON
        uint128 jurorLockPerCase; // sec. 48: 2 MON
        uint128 nonRevealSlash; // sec. 48: 1 MON
    }

    // --------------------------------------------------------------------
    // Bounds — compile-time, never bypassable
    // --------------------------------------------------------------------

    uint16 public constant BPS_DENOMINATOR = 10_000;

    // Lower bounds that are zero are omitted deliberately: the unsigned type
    // already enforces them, and a MIN_ constant that no check reads would
    // suggest a validation that does not exist.
    uint16 public constant MAX_PROTOCOL_FEE_BPS = 1_000; // 10% hard ceiling

    uint16 public constant MAX_COVERAGE_BPS = BPS_DENOMINATOR;

    /// @dev The multiplier may never take coverage below half or above double
    ///      the tier baseline, whatever the risk service asks for.
    uint16 public constant MIN_COVERAGE_MULTIPLIER_BPS = 5_000; // 0.5x
    uint16 public constant MAX_COVERAGE_MULTIPLIER_BPS = 20_000; // 2x

    uint8 public constant MIN_ACTIVE_CUSTODY = 1;
    uint8 public constant MAX_ACTIVE_CUSTODY = 10;

    uint8 public constant MIN_CUSTOMER_LISTINGS = 1;
    uint8 public constant MAX_CUSTOMER_LISTINGS = 50;

    uint8 public constant MIN_JURY_SIZE = 3;
    uint8 public constant MAX_JURY_SIZE = 15;

    uint32 public constant MIN_FUNDING_WINDOW = 5 minutes;
    uint32 public constant MAX_FUNDING_WINDOW = 24 hours;

    // Lifecycle windows the sec. 48 table does not list. Every non-terminal
    // delivery state needs a deadline: without one a stalled delivery has no
    // exit and its escrow cannot be recovered by anyone. Defaults live in
    // BaselineParams; the bounds are here.
    uint32 public constant MIN_LIFECYCLE_WINDOW = 10 minutes;
    uint32 public constant MAX_LIFECYCLE_WINDOW = 30 days;

    uint32 public constant MIN_CHALLENGE_WINDOW = 1 hours;
    uint32 public constant MAX_CHALLENGE_WINDOW = 7 days;

    uint32 public constant MAX_WITHDRAWAL_COOLDOWN = 30 days; // zero cooldown is allowed

    uint32 public constant MIN_QUOTE_VALIDITY = 1 minutes;
    uint32 public constant MAX_QUOTE_VALIDITY = 1 hours;

    uint32 public constant MIN_POD_VALIDITY = 1 minutes;
    uint32 public constant MAX_POD_VALIDITY = 1 hours;

    uint32 public constant MIN_REWARD_CLAIM_WINDOW = 7 days;
    uint32 public constant MAX_REWARD_CLAIM_WINDOW = 365 days;

    uint32 public constant MIN_REWARD_RECLAIM_DELAY = 1 days;
    uint32 public constant MAX_REWARD_RECLAIM_DELAY = 90 days;

    uint128 public constant MIN_COURIER_DEPOSIT = 0.001 ether;
    uint128 public constant MAX_COURIER_DEPOSIT = 1_000 ether;

    uint128 public constant MIN_JUROR_STAKE_FLOOR = 0.001 ether;
    uint128 public constant MAX_JUROR_STAKE_CEILING = 1_000 ether;

    uint64 public constant MIN_CONFIG_TIMELOCK = 1 hours;
    uint64 public constant MAX_CONFIG_TIMELOCK = 30 days;

    // --------------------------------------------------------------------
    // State
    // --------------------------------------------------------------------

    ProtocolAccessManager public immutable accessManager;

    /// @notice Delay between proposing and executing a configuration change.
    uint64 public immutable configTimelock;

    /// @notice Increments on every executed change. Never decreases.
    uint64 public configVersion;

    Params private _params;

    Params private _pendingParams;
    uint64 private _pendingReadyAt;

    address public treasury;
    address public riskQuoteSigner;
    address public podAttestationSigner;
    address public randomnessAdapter;

    address private _pendingTreasury;
    uint64 private _pendingTreasuryReadyAt;

    address private _pendingRandomnessAdapter;
    uint64 private _pendingRandomnessAdapterReadyAt;

    // --------------------------------------------------------------------
    // Events (sec. 34: configuration events are on-chain)
    // --------------------------------------------------------------------

    event ParamsProposed(uint64 indexed forVersion, uint64 readyAt, Params params);
    event ParamsProposalCancelled(uint64 indexed forVersion);
    event ParamsUpdated(uint64 indexed newVersion, Params params);

    event TreasuryProposed(address indexed newTreasury, uint64 readyAt);
    event TreasuryUpdated(address indexed previousTreasury, address indexed newTreasury);

    event RandomnessAdapterProposed(address indexed newAdapter, uint64 readyAt);
    event RandomnessAdapterUpdated(address indexed previousAdapter, address indexed newAdapter);

    event RiskQuoteSignerRotated(address indexed previousSigner, address indexed newSigner);
    event PodAttestationSignerRotated(address indexed previousSigner, address indexed newSigner);

    // --------------------------------------------------------------------
    // Errors
    // --------------------------------------------------------------------

    error ZeroAddress();
    error TimelockOutOfBounds(uint64 provided);
    error NoPendingProposal();
    error ProposalNotReady(uint64 readyAt);
    error OutOfBounds(string parameter);
    error InvalidCoverageOrdering();
    error InvalidJuryOrdering();
    error InvalidJurorEconomics();
    error JurySizeMustBeOdd(uint8 size);

    // --------------------------------------------------------------------
    // Modifiers
    // --------------------------------------------------------------------

    modifier onlyConfigAdmin() {
        _checkConfigAdmin();
        _;
    }

    modifier onlySignerAdmin() {
        _checkSignerAdmin();
        _;
    }

    function _checkConfigAdmin() internal view {
        accessManager.requireRole(accessManager.CONFIG_ADMIN_ROLE(), msg.sender);
    }

    function _checkSignerAdmin() internal view {
        accessManager.requireRole(accessManager.SIGNER_ADMIN_ROLE(), msg.sender);
    }

    // --------------------------------------------------------------------
    // Construction
    // --------------------------------------------------------------------

    constructor(
        ProtocolAccessManager accessManager_,
        uint64 configTimelock_,
        Params memory initialParams,
        address treasury_,
        address riskQuoteSigner_,
        address podAttestationSigner_
    ) {
        if (address(accessManager_) == address(0)) revert ZeroAddress();
        if (treasury_ == address(0)) revert ZeroAddress();
        if (riskQuoteSigner_ == address(0)) revert ZeroAddress();
        if (podAttestationSigner_ == address(0)) revert ZeroAddress();
        if (configTimelock_ < MIN_CONFIG_TIMELOCK || configTimelock_ > MAX_CONFIG_TIMELOCK) {
            revert TimelockOutOfBounds(configTimelock_);
        }

        _validate(initialParams);

        accessManager = accessManager_;
        configTimelock = configTimelock_;
        _params = initialParams;
        treasury = treasury_;
        riskQuoteSigner = riskQuoteSigner_;
        podAttestationSigner = podAttestationSigner_;
        configVersion = 1;

        emit ParamsUpdated(1, initialParams);
        emit TreasuryUpdated(address(0), treasury_);
        emit RiskQuoteSignerRotated(address(0), riskQuoteSigner_);
        emit PodAttestationSignerRotated(address(0), podAttestationSigner_);
    }

    // --------------------------------------------------------------------
    // Reads
    // --------------------------------------------------------------------

    function params() external view returns (Params memory) {
        return _params;
    }

    function pendingParams() external view returns (Params memory, uint64 readyAt) {
        return (_pendingParams, _pendingReadyAt);
    }

    function protocolFeeBps() external view returns (uint16) {
        return _params.protocolFeeBps;
    }

    function courierBaseDeposit() external view returns (uint128) {
        return _params.courierBaseDeposit;
    }

    function maxActiveCustody() external view returns (uint8) {
        return _params.maxActiveCustody;
    }

    function fundingWindow() external view returns (uint32) {
        return _params.fundingWindow;
    }

    function challengeWindow() external view returns (uint32) {
        return _params.challengeWindow;
    }

    function biddingWindow() external view returns (uint32) {
        return _params.biddingWindow;
    }

    function pickupWindow() external view returns (uint32) {
        return _params.pickupWindow;
    }

    function transitWindow() external view returns (uint32) {
        return _params.transitWindow;
    }

    function returnWindow() external view returns (uint32) {
        return _params.returnWindow;
    }

    function customerMaxActiveListings() external view returns (uint8) {
        return _params.customerMaxActiveListings;
    }

    function courierWithdrawalCooldown() external view returns (uint32) {
        return _params.courierWithdrawalCooldown;
    }

    function coverageMultiplierMinBps() external view returns (uint16) {
        return _params.coverageMultiplierMinBps;
    }

    function coverageMultiplierMaxBps() external view returns (uint16) {
        return _params.coverageMultiplierMaxBps;
    }

    function riskQuoteValidity() external view returns (uint32) {
        return _params.riskQuoteValidity;
    }

    function podAttestationValidity() external view returns (uint32) {
        return _params.podAttestationValidity;
    }

    function ratingWindow() external view returns (uint32) {
        return _params.ratingWindow;
    }

    function rewardClaimWindow() external view returns (uint32) {
        return _params.rewardClaimWindow;
    }

    function rewardReclaimDelay() external view returns (uint32) {
        return _params.rewardReclaimDelay;
    }

    /// @notice Coverage basis points for a risk tier. Tier 4 (R4) is disabled per sec. 49.
    function coverageBpsForTier(uint8 tier) external view returns (uint16) {
        if (tier == 1) return _params.coverageBpsR1;
        if (tier == 2) return _params.coverageBpsR2;
        if (tier == 3) return _params.coverageBpsR3;
        revert OutOfBounds("riskTier");
    }

    // --------------------------------------------------------------------
    // Parameter changes (timelocked)
    // --------------------------------------------------------------------

    /// @notice Propose a complete new parameter set. Validated now and again on execution.
    function proposeParams(Params calldata newParams) external onlyConfigAdmin {
        _validate(newParams);
        _pendingParams = newParams;
        uint64 readyAt = SafeCast.toUint64(block.timestamp) + configTimelock;
        _pendingReadyAt = readyAt;
        emit ParamsProposed(configVersion + 1, readyAt, newParams);
    }

    /// @notice Discard a pending parameter proposal.
    function cancelParamsProposal() external onlyConfigAdmin {
        if (_pendingReadyAt == 0) revert NoPendingProposal();
        _pendingReadyAt = 0;
        delete _pendingParams;
        emit ParamsProposalCancelled(configVersion + 1);
    }

    /**
     * @notice Apply a pending parameter proposal once its timelock has elapsed.
     * @dev Re-validates. Bounds are checked at execution as well as proposal, so a
     *      proposal cannot be used to smuggle a value past a later bound change.
     */
    function executeParams() external onlyConfigAdmin {
        uint64 readyAt = _pendingReadyAt;
        if (readyAt == 0) revert NoPendingProposal();
        if (block.timestamp < readyAt) revert ProposalNotReady(readyAt);

        Params memory next = _pendingParams;
        _validate(next);

        _params = next;
        _pendingReadyAt = 0;
        delete _pendingParams;

        uint64 newVersion = configVersion + 1;
        configVersion = newVersion;
        emit ParamsUpdated(newVersion, next);
    }

    // --------------------------------------------------------------------
    // Address changes
    // --------------------------------------------------------------------

    function proposeTreasury(address newTreasury) external onlyConfigAdmin {
        if (newTreasury == address(0)) revert ZeroAddress();
        _pendingTreasury = newTreasury;
        uint64 readyAt = SafeCast.toUint64(block.timestamp) + configTimelock;
        _pendingTreasuryReadyAt = readyAt;
        emit TreasuryProposed(newTreasury, readyAt);
    }

    function executeTreasury() external onlyConfigAdmin {
        uint64 readyAt = _pendingTreasuryReadyAt;
        if (readyAt == 0) revert NoPendingProposal();
        if (block.timestamp < readyAt) revert ProposalNotReady(readyAt);
        address previous = treasury;
        treasury = _pendingTreasury;
        _pendingTreasuryReadyAt = 0;
        _pendingTreasury = address(0);
        emit TreasuryUpdated(previous, treasury);
    }

    function proposeRandomnessAdapter(address newAdapter) external onlyConfigAdmin {
        if (newAdapter == address(0)) revert ZeroAddress();
        _pendingRandomnessAdapter = newAdapter;
        uint64 readyAt = SafeCast.toUint64(block.timestamp) + configTimelock;
        _pendingRandomnessAdapterReadyAt = readyAt;
        emit RandomnessAdapterProposed(newAdapter, readyAt);
    }

    function executeRandomnessAdapter() external onlyConfigAdmin {
        uint64 readyAt = _pendingRandomnessAdapterReadyAt;
        if (readyAt == 0) revert NoPendingProposal();
        if (block.timestamp < readyAt) revert ProposalNotReady(readyAt);
        address previous = randomnessAdapter;
        randomnessAdapter = _pendingRandomnessAdapter;
        _pendingRandomnessAdapterReadyAt = 0;
        _pendingRandomnessAdapter = address(0);
        emit RandomnessAdapterUpdated(previous, randomnessAdapter);
    }

    /// @notice Rotate the risk-quote signer immediately. See contract-level note on timing.
    function rotateRiskQuoteSigner(address newSigner) external onlySignerAdmin {
        if (newSigner == address(0)) revert ZeroAddress();
        address previous = riskQuoteSigner;
        riskQuoteSigner = newSigner;
        emit RiskQuoteSignerRotated(previous, newSigner);
    }

    /// @notice Rotate the PoD attestation signer immediately. See contract-level note on timing.
    function rotatePodAttestationSigner(address newSigner) external onlySignerAdmin {
        if (newSigner == address(0)) revert ZeroAddress();
        address previous = podAttestationSigner;
        podAttestationSigner = newSigner;
        emit PodAttestationSignerRotated(previous, newSigner);
    }

    // --------------------------------------------------------------------
    // Validation
    // --------------------------------------------------------------------

    function _validate(Params memory p) internal pure {
        _validateEconomics(p);
        _validateLimits(p);
        _validateWindows(p);
        _validateStakes(p);
    }

    function _validateEconomics(Params memory p) internal pure {
        if (p.protocolFeeBps > MAX_PROTOCOL_FEE_BPS) revert OutOfBounds("protocolFeeBps");
        if (p.coverageBpsR1 > MAX_COVERAGE_BPS) revert OutOfBounds("coverageBpsR1");
        if (p.coverageBpsR2 > MAX_COVERAGE_BPS) revert OutOfBounds("coverageBpsR2");
        if (p.coverageBpsR3 > MAX_COVERAGE_BPS) revert OutOfBounds("coverageBpsR3");
        // Higher risk tier must never require less coverage than a lower one (sec. 6).
        if (p.coverageBpsR1 > p.coverageBpsR2 || p.coverageBpsR2 > p.coverageBpsR3) {
            revert InvalidCoverageOrdering();
        }

        if (
            p.coverageMultiplierMinBps < MIN_COVERAGE_MULTIPLIER_BPS
                || p.coverageMultiplierMinBps > MAX_COVERAGE_MULTIPLIER_BPS
        ) {
            revert OutOfBounds("coverageMultiplierMinBps");
        }
        if (
            p.coverageMultiplierMaxBps < MIN_COVERAGE_MULTIPLIER_BPS
                || p.coverageMultiplierMaxBps > MAX_COVERAGE_MULTIPLIER_BPS
        ) {
            revert OutOfBounds("coverageMultiplierMaxBps");
        }
        if (p.coverageMultiplierMinBps > p.coverageMultiplierMaxBps) revert InvalidCoverageOrdering();
    }

    function _validateLimits(Params memory p) internal pure {
        if (p.maxActiveCustody < MIN_ACTIVE_CUSTODY || p.maxActiveCustody > MAX_ACTIVE_CUSTODY) {
            revert OutOfBounds("maxActiveCustody");
        }
        if (p.customerMaxActiveListings < MIN_CUSTOMER_LISTINGS || p.customerMaxActiveListings > MAX_CUSTOMER_LISTINGS)
        {
            revert OutOfBounds("customerMaxActiveListings");
        }

        _validateJurySize(p.juryFirstSize);
        _validateJurySize(p.juryAppeal1Size);
        _validateJurySize(p.juryAppeal2Size);
        // Each appeal round must be strictly larger than the previous one (sec. 28).
        if (p.juryFirstSize >= p.juryAppeal1Size || p.juryAppeal1Size >= p.juryAppeal2Size) {
            revert InvalidJuryOrdering();
        }
    }

    function _validateWindows(Params memory p) internal pure {
        if (p.fundingWindow < MIN_FUNDING_WINDOW || p.fundingWindow > MAX_FUNDING_WINDOW) {
            revert OutOfBounds("fundingWindow");
        }
        _validateLifecycleWindow(p.biddingWindow, "biddingWindow");
        _validateLifecycleWindow(p.pickupWindow, "pickupWindow");
        _validateLifecycleWindow(p.transitWindow, "transitWindow");
        _validateLifecycleWindow(p.returnWindow, "returnWindow");
        _validateLifecycleWindow(p.ratingWindow, "ratingWindow");
        if (p.challengeWindow < MIN_CHALLENGE_WINDOW || p.challengeWindow > MAX_CHALLENGE_WINDOW) {
            revert OutOfBounds("challengeWindow");
        }
        if (p.courierWithdrawalCooldown > MAX_WITHDRAWAL_COOLDOWN) {
            revert OutOfBounds("courierWithdrawalCooldown");
        }
        if (p.riskQuoteValidity < MIN_QUOTE_VALIDITY || p.riskQuoteValidity > MAX_QUOTE_VALIDITY) {
            revert OutOfBounds("riskQuoteValidity");
        }
        if (p.podAttestationValidity < MIN_POD_VALIDITY || p.podAttestationValidity > MAX_POD_VALIDITY) {
            revert OutOfBounds("podAttestationValidity");
        }
        if (p.rewardClaimWindow < MIN_REWARD_CLAIM_WINDOW || p.rewardClaimWindow > MAX_REWARD_CLAIM_WINDOW) {
            revert OutOfBounds("rewardClaimWindow");
        }
        if (p.rewardReclaimDelay < MIN_REWARD_RECLAIM_DELAY || p.rewardReclaimDelay > MAX_REWARD_RECLAIM_DELAY) {
            revert OutOfBounds("rewardReclaimDelay");
        }
    }

    function _validateStakes(Params memory p) internal pure {
        if (p.courierBaseDeposit < MIN_COURIER_DEPOSIT || p.courierBaseDeposit > MAX_COURIER_DEPOSIT) {
            revert OutOfBounds("courierBaseDeposit");
        }
        if (p.minJurorStake < MIN_JUROR_STAKE_FLOOR || p.minJurorStake > MAX_JUROR_STAKE_CEILING) {
            revert OutOfBounds("minJurorStake");
        }
        // A juror can never be asked to lock more than the minimum stake, and can
        // never be slashed for more than is locked for the case (sec. 27).
        if (p.jurorLockPerCase > p.minJurorStake) revert InvalidJurorEconomics();
        if (p.nonRevealSlash > p.jurorLockPerCase) revert InvalidJurorEconomics();
    }

    function _validateLifecycleWindow(uint32 window, string memory name) internal pure {
        if (window < MIN_LIFECYCLE_WINDOW || window > MAX_LIFECYCLE_WINDOW) revert OutOfBounds(name);
    }

    function _validateJurySize(uint8 size) internal pure {
        if (size < MIN_JURY_SIZE || size > MAX_JURY_SIZE) revert OutOfBounds("jurySize");
        // Even panels can deadlock; sec. 28 uses 3/5/7 throughout.
        if (size % 2 == 0) revert JurySizeMustBeOdd(size);
    }
}
