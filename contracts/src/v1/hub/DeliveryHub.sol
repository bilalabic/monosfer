// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {ProtocolAccessManager} from "../access/ProtocolAccessManager.sol";
import {ProtocolConfig} from "../config/ProtocolConfig.sol";
import {CourierRegistry} from "../registry/CourierRegistry.sol";
import {ISettlementVault} from "../interfaces/ISettlementVault.sol";
import {PickupProof} from "../proof/PickupProof.sol";
import {PickupProofVerifier} from "../proof/PickupProofVerifier.sol";
import {CoverageQuote} from "../risk/CoverageQuote.sol";
import {RiskQuoteVerifier} from "../risk/RiskQuoteVerifier.sol";

/**
 * @title DeliveryHub
 * @notice The delivery lifecycle: creation, bidding, selection, funding,
 *         custody transitions and settlement.
 * @dev Baseline refs: sec. 7 (bidding), sec. 10 (funding session), sec. 11 (state
 *      machine), sec. 16 (challenge window), sec. 17 (return), sec. 18
 *      (settlement), sec. 48 (windows), invariants sec. 33-2, sec. 33-6,
 *      sec. 33-16 and sec. 33-17.
 *
 *      ## Nothing is escrowed until both sides commit
 *
 *      Creating a delivery costs nothing and locks nothing. Money enters only
 *      after a bid is selected and both parties fund the session (sec. 10), so an
 *      unbid or abandoned listing has no value to strand: it simply expires.
 *
 *      ## Every live state has a deadline
 *
 *      Each non-terminal state carries `stateDeadline`. Once it passes, anyone
 *      may call `poke`, which advances the delivery toward a terminal state and
 *      releases whatever is held. The guarantee is that no participant ever needs
 *      the other's cooperation to recover their funds, and no delivery can sit
 *      indefinitely holding value.
 *
 *      Timeouts resolve deterministically and never open a jury case (sec. 26).
 *      Fault-based outcomes need evidence and belong to the dispute court.
 *
 *      ## Selection cost does not grow with the number of bids
 *
 *      Placing a bid reserves collateral in CourierRegistry; a courier who is not
 *      selected releases their own reservation with `withdrawBid`. Nothing
 *      iterates a bidder list, so `selectCourier` costs the same whether three
 *      couriers bid or three thousand (sec. 45).
 *
 *      ## Terms are fixed by a signed quote and by the selected bid
 *
 *      The risk tier and required coverage come from a coverage quote signed by
 *      the risk service and re-bounded on-chain (sec. 6, sec. 8.3). Price and ETA
 *      come from the bid version the customer explicitly selects, so a courier
 *      cannot re-price between being read and being chosen.
 *
 *      ## Custody changes hands only when both sides are present
 *
 *      `confirmPickup` is sent by the courier and carries the sender's
 *      signed acceptance of the handover (sec. 12). Neither party can move
 *      the package into transit alone.
 */
contract DeliveryHub is ReentrancyGuard, RiskQuoteVerifier, PickupProofVerifier {
    // --------------------------------------------------------------------
    // State machine (sec. 11)
    // --------------------------------------------------------------------

    enum State {
        None,
        Bidding,
        AwaitingFunding,
        ReadyForPickup,
        InTransit,
        DeliveredPending,
        ReturnRequired,
        // terminal from here down
        Completed,
        Returned,
        Cancelled,
        Expired
    }

    /// @dev First terminal state. Everything at or after it can never transition.
    State private constant FIRST_TERMINAL = State.Completed;

    struct Delivery {
        address customer;
        address courier;
        State state;
        uint8 riskTier;
        uint32 termsVersion;
        uint64 stateDeadline;
        uint96 courierAsk;
        uint96 protocolFee;
        uint96 returnReserve;
        uint96 requiredCollateral;
        bool customerFunded;
        bool courierFunded;
    }

    struct Bid {
        uint96 courierAsk;
        uint96 returnAsk;
        uint32 etaMinutes;
        uint64 validUntil;
        uint32 termsVersion;
        bool active;
    }

    // --------------------------------------------------------------------
    // Storage
    // --------------------------------------------------------------------

    ProtocolAccessManager public immutable accessManager;
    ProtocolConfig public immutable config;
    CourierRegistry public immutable registry;
    ISettlementVault public immutable vault;

    uint256 public nextDeliveryId;

    mapping(uint256 => Delivery) private _deliveries;
    mapping(uint256 => mapping(address => Bid)) private _bids;
    mapping(address => uint32) public activeListings;

    /// @notice Collateral a courier reserves to place one bid.
    uint96 public immutable bidDeposit;

    // --------------------------------------------------------------------
    // Events
    // --------------------------------------------------------------------

    event DeliveryCreated(
        uint256 indexed deliveryId,
        address indexed customer,
        uint8 riskTier,
        uint96 requiredCollateral,
        uint64 deadline,
        bytes32 quoteDigest
    );
    event BidPlaced(
        uint256 indexed deliveryId,
        address indexed courier,
        uint96 courierAsk,
        uint96 returnAsk,
        uint32 etaMinutes,
        uint64 validUntil,
        uint32 termsVersion
    );
    event BidWithdrawn(uint256 indexed deliveryId, address indexed courier);
    event CourierSelected(uint256 indexed deliveryId, address indexed courier, uint96 courierAsk, uint96 protocolFee);
    event CustomerFunded(uint256 indexed deliveryId, uint256 amount);
    /// @param reservedBase Coverage met from stake the courier already held.
    /// @param additionalBond Coverage the courier had to post for this delivery.
    event CourierFunded(
        uint256 indexed deliveryId, address indexed courier, uint256 reservedBase, uint256 additionalBond
    );
    event StateChanged(uint256 indexed deliveryId, State from, State to, uint64 deadline);
    event PickupConfirmed(uint256 indexed deliveryId, address indexed courier);
    event DeliveryProofSubmitted(uint256 indexed deliveryId, address indexed courier);
    event ReturnRequested(uint256 indexed deliveryId, address indexed by);
    event Settled(uint256 indexed deliveryId, State finalState);

    // --------------------------------------------------------------------
    // Errors
    // --------------------------------------------------------------------

    error ZeroAddress();
    error ZeroAmount();
    error UnknownDelivery(uint256 deliveryId);
    error WrongState(uint256 deliveryId, State actual, State expected);
    error NotCustomer(address caller);
    error NotCourier(address caller);
    error SelfDealing();
    error TooManyActiveListings(uint32 limit);
    error NoActiveBid(address courier);
    error BidExpired(uint64 validUntil);
    error BidInvalid();
    error TermsVersionMismatch(uint32 expected, uint32 actual);
    error CourierNotEligible(address courier, uint8 riskTier);
    error IncorrectFundingAmount(uint256 expected, uint256 provided);
    error AlreadyFunded();
    error DeadlineNotReached(uint64 deadline);
    error InsufficientBond(uint256 required, uint256 provided);

    // --------------------------------------------------------------------
    // Modifiers
    // --------------------------------------------------------------------

    modifier whenNotPaused() {
        _checkNotPaused();
        _;
    }

    function _checkNotPaused() internal view {
        accessManager.requireNotPaused();
    }

    constructor(
        ProtocolAccessManager accessManager_,
        ProtocolConfig config_,
        CourierRegistry registry_,
        ISettlementVault vault_,
        uint96 bidDeposit_
    ) {
        if (address(accessManager_) == address(0)) revert ZeroAddress();
        if (address(config_) == address(0)) revert ZeroAddress();
        if (address(registry_) == address(0)) revert ZeroAddress();
        if (address(vault_) == address(0)) revert ZeroAddress();
        if (bidDeposit_ == 0) revert ZeroAmount();

        accessManager = accessManager_;
        config = config_;
        registry = registry_;
        vault = vault_;
        bidDeposit = bidDeposit_;
    }

    // --------------------------------------------------------------------
    // Creation and bidding
    // --------------------------------------------------------------------

    /**
     * @notice Publish a delivery for bidding. Takes no payment (sec. 10).
     * @dev The risk tier and required coverage come from the signed quote, never
     *      from the caller, so a customer cannot choose their own coverage
     *      (sec. 6, sec. 8.3).
     * @param quote Signed coverage quote, issued to `msg.sender`.
     * @param signature EOA or ERC-1271 signature over the quote digest.
     * @return deliveryId Identifier of the published delivery.
     */
    function createDelivery(CoverageQuote.Quote calldata quote, bytes calldata signature)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 deliveryId)
    {
        bytes32 quoteDigest = _redeemQuote(config, quote, signature);
        uint8 riskTier = quote.riskTier;
        uint96 requiredCollateral = quote.requiredCoverage;
        if (requiredCollateral == 0) revert ZeroAmount();

        uint32 limit = config.customerMaxActiveListings();
        if (activeListings[msg.sender] >= limit) revert TooManyActiveListings(limit);

        deliveryId = nextDeliveryId++;
        uint64 deadline = SafeCast.toUint64(block.timestamp) + config.biddingWindow();

        _deliveries[deliveryId] = Delivery({
            customer: msg.sender,
            courier: address(0),
            state: State.Bidding,
            riskTier: riskTier,
            termsVersion: 0,
            stateDeadline: deadline,
            courierAsk: 0,
            protocolFee: 0,
            returnReserve: 0,
            requiredCollateral: requiredCollateral,
            customerFunded: false,
            courierFunded: false
        });
        activeListings[msg.sender] += 1;

        emit DeliveryCreated(deliveryId, msg.sender, riskTier, requiredCollateral, deadline, quoteDigest);
        emit StateChanged(deliveryId, State.None, State.Bidding, deadline);
    }

    /**
     * @notice Place or replace a bid (sec. 7).
     * @dev A courier has one active bid version per delivery. Replacing reuses the
     *      existing reservation instead of stacking a second one.
     */
    function placeBid(uint256 deliveryId, uint96 courierAsk, uint96 returnAsk, uint32 etaMinutes, uint64 validUntil)
        external
        nonReentrant
        whenNotPaused
    {
        Delivery storage d = _requireDelivery(deliveryId);
        _requireState(deliveryId, d, State.Bidding);
        if (block.timestamp > d.stateDeadline) revert BidExpired(d.stateDeadline);

        if (courierAsk == 0) revert ZeroAmount();
        if (etaMinutes == 0) revert BidInvalid();
        if (validUntil <= block.timestamp) revert BidExpired(validUntil);
        // A customer bidding on their own delivery is rejected here as well as at
        // selection, so self-dealing never even reaches the customer's choice.
        if (msg.sender == d.customer) revert SelfDealing();
        if (!registry.isEligibleFor(msg.sender, d.riskTier)) {
            revert CourierNotEligible(msg.sender, d.riskTier);
        }

        Bid storage b = _bids[deliveryId][msg.sender];
        bool isNew = !b.active;

        b.courierAsk = courierAsk;
        b.returnAsk = returnAsk;
        b.etaMinutes = etaMinutes;
        b.validUntil = validUntil;
        b.termsVersion += 1;
        b.active = true;

        emit BidPlaced(deliveryId, msg.sender, courierAsk, returnAsk, etaMinutes, validUntil, b.termsVersion);

        if (isNew) {
            registry.reserveCollateral(msg.sender, bidDeposit);
        }
    }

    /**
     * @notice Withdraw an unselected bid and release its reservation (sec. 7).
     * @dev Pull-based on purpose. Losing couriers free their own collateral, so
     *      selection never iterates a bidder list (sec. 45).
     */
    function withdrawBid(uint256 deliveryId) external nonReentrant {
        Delivery storage d = _requireDelivery(deliveryId);
        Bid storage b = _bids[deliveryId][msg.sender];
        if (!b.active) revert NoActiveBid(msg.sender);
        // The selected courier's collateral is governed by the delivery, not by
        // the bid, so they cannot withdraw it here.
        if (d.courier == msg.sender) revert WrongState(deliveryId, d.state, State.Bidding);

        b.active = false;
        emit BidWithdrawn(deliveryId, msg.sender);
        registry.releaseCollateral(msg.sender, bidDeposit);
    }

    /**
     * @notice Select a courier and freeze the terms (sec. 7).
     * @dev Invariant sec. 33-16: a customer can never select their own wallet.
     */
    function selectCourier(uint256 deliveryId, address courier, uint32 expectedTermsVersion)
        external
        nonReentrant
        whenNotPaused
    {
        Delivery storage d = _requireDelivery(deliveryId);
        _requireState(deliveryId, d, State.Bidding);
        if (msg.sender != d.customer) revert NotCustomer(msg.sender);
        if (courier == d.customer) revert SelfDealing();

        Bid storage b = _bids[deliveryId][courier];
        if (!b.active) revert NoActiveBid(courier);
        if (block.timestamp > b.validUntil) revert BidExpired(b.validUntil);
        // The customer commits to the exact bid version they saw. A courier
        // cannot re-price between the customer reading the bid and selecting it.
        if (b.termsVersion != expectedTermsVersion) revert TermsVersionMismatch(expectedTermsVersion, b.termsVersion);
        if (!registry.isEligibleFor(courier, d.riskTier)) revert CourierNotEligible(courier, d.riskTier);

        uint96 fee = SafeCast.toUint96((uint256(b.courierAsk) * config.protocolFeeBps()) / BPS_DENOMINATOR);

        d.courier = courier;
        d.courierAsk = b.courierAsk;
        d.returnReserve = b.returnAsk;
        d.protocolFee = fee;
        d.termsVersion = b.termsVersion;

        _transition(deliveryId, d, State.AwaitingFunding, config.fundingWindow());
        emit CourierSelected(deliveryId, courier, b.courierAsk, fee);
    }

    // --------------------------------------------------------------------
    // Funding session (sec. 10)
    // --------------------------------------------------------------------

    /// @notice Total the customer must send: ask + protocol fee + return reserve (sec. 8.1).
    function customerFundingAmount(uint256 deliveryId) public view returns (uint256) {
        Delivery storage d = _deliveries[deliveryId];
        return uint256(d.courierAsk) + d.protocolFee + d.returnReserve;
    }

    /**
     * @notice Customer locks escrow.
     * @dev Invariant sec. 33-17: the amount must match the selected terms exactly.
     */
    function fundAsCustomer(uint256 deliveryId) external payable nonReentrant whenNotPaused {
        Delivery storage d = _requireDelivery(deliveryId);
        _requireState(deliveryId, d, State.AwaitingFunding);
        if (msg.sender != d.customer) revert NotCustomer(msg.sender);
        if (d.customerFunded) revert AlreadyFunded();

        uint256 expected = customerFundingAmount(deliveryId);
        if (msg.value != expected) revert IncorrectFundingAmount(expected, msg.value);

        d.customerFunded = true;
        emit CustomerFunded(deliveryId, msg.value);

        vault.lock{value: msg.value}(escrowLockId(deliveryId), d.customer);
        _maybeReady(deliveryId, d);
    }

    /**
     * @notice Courier locks the required coverage.
     * @dev Any MON sent is added to the courier's stake first, so a courier short
     *      of the required coverage can top up and fund in one transaction
     *      (sec. 8.3 additional bond).
     */
    function fundAsCourier(uint256 deliveryId) external payable nonReentrant whenNotPaused {
        Delivery storage d = _requireDelivery(deliveryId);
        _requireState(deliveryId, d, State.AwaitingFunding);
        if (msg.sender != d.courier) revert NotCourier(msg.sender);
        if (d.courierFunded) revert AlreadyFunded();

        // sec. 8.3 splits coverage into what the courier already had and what
        // they must add. The bid reservation counts toward the first part, so it
        // is folded in rather than released and re-taken.
        uint256 coverage = d.requiredCollateral;
        uint256 availableBefore = registry.availableStake(msg.sender) + bidDeposit;
        uint256 reservedBase = availableBefore < coverage ? availableBefore : coverage;
        uint256 additionalBond = coverage - reservedBase;

        if (additionalBond > 0 && msg.value < additionalBond) {
            revert InsufficientBond(additionalBond, msg.value);
        }
        if (msg.value > 0) registry.depositStakeFor{value: msg.value}(msg.sender);

        d.courierFunded = true;
        _bids[deliveryId][msg.sender].active = false;
        emit CourierFunded(deliveryId, msg.sender, reservedBase, additionalBond);

        uint256 extra = coverage > bidDeposit ? coverage - bidDeposit : 0;
        if (extra > 0) registry.reserveCollateral(msg.sender, extra);
        _maybeReady(deliveryId, d);
    }

    function _maybeReady(uint256 deliveryId, Delivery storage d) internal {
        if (d.customerFunded && d.courierFunded) {
            _transition(deliveryId, d, State.ReadyForPickup, config.pickupWindow());
        }
    }

    // --------------------------------------------------------------------
    // Physical lifecycle
    // --------------------------------------------------------------------

    /**
     * @notice Courier takes custody. Moves straight to IN_TRANSIT (sec. 11).
     * @dev Both sides must be present: the courier sends the transaction and the
     *      sender's EIP-712 acceptance authorises the handover (sec. 12). The
     *      acceptance is validated and its nonce burned before the state moves,
     *      so a failed proof leaves the delivery exactly where it was.
     * @param deliveryId The delivery being picked up.
     * @param acceptance The sender's signed acceptance of this handover.
     * @param signature EOA or ERC-1271 signature over `hashPickupAcceptance`.
     */
    function confirmPickup(uint256 deliveryId, PickupProof.Acceptance calldata acceptance, bytes calldata signature)
        external
        nonReentrant
        whenNotPaused
    {
        Delivery storage d = _requireDelivery(deliveryId);
        _requireState(deliveryId, d, State.ReadyForPickup);
        if (msg.sender != d.courier) revert NotCourier(msg.sender);

        _consumePickupAcceptance(deliveryId, d.courier, d.customer, acceptance, signature);

        emit PickupConfirmed(deliveryId, d.courier);
        _transition(deliveryId, d, State.InTransit, config.transitWindow());
        registry.openCustody(d.courier);
    }

    /**
     * @notice Courier submits delivery proof, opening the challenge window (sec. 16).
     * @dev Authorisation is currently the caller check; P2 replaces it with a
     *      signed proof-of-delivery attestation.
     */
    function submitDeliveryProof(uint256 deliveryId) external nonReentrant whenNotPaused {
        Delivery storage d = _requireDelivery(deliveryId);
        _requireState(deliveryId, d, State.InTransit);
        if (msg.sender != d.courier) revert NotCourier(msg.sender);

        emit DeliveryProofSubmitted(deliveryId, d.courier);
        _transition(deliveryId, d, State.DeliveredPending, config.challengeWindow());
        registry.closeCustody(d.courier);
    }

    /// @notice Customer confirms early, completing before the challenge window ends (sec. 16).
    function confirmDelivery(uint256 deliveryId) external nonReentrant whenNotPaused {
        Delivery storage d = _requireDelivery(deliveryId);
        _requireState(deliveryId, d, State.DeliveredPending);
        if (msg.sender != d.customer) revert NotCustomer(msg.sender);
        _complete(deliveryId, d);
    }

    /// @notice Either party marks the delivery as needing to go back (sec. 17).
    function requestReturn(uint256 deliveryId) external nonReentrant whenNotPaused {
        Delivery storage d = _requireDelivery(deliveryId);
        _requireState(deliveryId, d, State.InTransit);
        if (msg.sender != d.courier && msg.sender != d.customer) revert NotCourier(msg.sender);

        _transition(deliveryId, d, State.ReturnRequired, config.returnWindow());
        emit ReturnRequested(deliveryId, msg.sender);
    }

    /// @notice Courier confirms the package is back with the sender (sec. 17).
    function confirmReturn(uint256 deliveryId) external nonReentrant whenNotPaused {
        Delivery storage d = _requireDelivery(deliveryId);
        _requireState(deliveryId, d, State.ReturnRequired);
        if (msg.sender != d.courier) revert NotCourier(msg.sender);

        registry.closeCustody(d.courier);
        _settleReturn(deliveryId, d, true);
    }

    // --------------------------------------------------------------------
    // The exit: anyone can advance a stalled delivery
    // --------------------------------------------------------------------

    /**
     * @notice Advance a delivery whose deadline has passed. Callable by anyone.
     * @dev This is what makes "no state without an exit" true. Each live state
     *      has exactly one timeout target, and every path ends terminal:
     *
     *        Bidding          -> Expired    (nothing was ever escrowed)
     *        AwaitingFunding  -> Cancelled  (whoever funded is refunded, sec. 10)
     *        ReadyForPickup   -> Cancelled  (courier never came; escrow refunded)
     *        InTransit        -> ReturnRequired (courier holds goods; must return)
     *        ReturnRequired   -> Returned   (deterministic, not a jury case, sec. 26)
     *        DeliveredPending -> Completed  (permissionless finalizer, sec. 16)
     */
    function poke(uint256 deliveryId) external nonReentrant {
        Delivery storage d = _requireDelivery(deliveryId);
        if (d.state >= FIRST_TERMINAL || d.state == State.None) {
            revert WrongState(deliveryId, d.state, State.Bidding);
        }
        if (block.timestamp <= d.stateDeadline) revert DeadlineNotReached(d.stateDeadline);

        State s = d.state;
        if (s == State.Bidding) {
            _finish(deliveryId, d, State.Expired);
        } else if (s == State.AwaitingFunding) {
            _cancelWithRefunds(deliveryId, d);
        } else if (s == State.ReadyForPickup) {
            _cancelWithRefunds(deliveryId, d);
        } else if (s == State.InTransit) {
            _transition(deliveryId, d, State.ReturnRequired, config.returnWindow());
            emit ReturnRequested(deliveryId, msg.sender);
        } else if (s == State.ReturnRequired) {
            // The window elapsed without a confirmed return. Resolve
            // deterministically: the customer is made whole and the courier's
            // coverage is released. Slashing requires evidence and belongs to
            // the dispute court (sec. 13, sec. 26).
            registry.closeCustody(d.courier);
            _settleReturn(deliveryId, d, false);
        } else {
            _complete(deliveryId, d);
        }
    }

    /// @notice Customer cancels while still in bidding, before anything is at stake.
    function cancelDuringBidding(uint256 deliveryId) external nonReentrant {
        Delivery storage d = _requireDelivery(deliveryId);
        _requireState(deliveryId, d, State.Bidding);
        if (msg.sender != d.customer) revert NotCustomer(msg.sender);
        _finish(deliveryId, d, State.Cancelled);
    }

    // --------------------------------------------------------------------
    // Settlement
    // --------------------------------------------------------------------

    function _complete(uint256 deliveryId, Delivery storage d) internal {
        ISettlementVault.Payout[] memory payouts = _successPayouts(d);
        _releaseCourierCollateral(d);
        _finish(deliveryId, d, State.Completed);
        emit Settled(deliveryId, State.Completed);
        vault.releaseLock(escrowLockId(deliveryId), payouts);
    }

    /// @dev sec. 18.1: ask to courier, fee to treasury, unused return reserve to customer.
    function _successPayouts(Delivery storage d) internal view returns (ISettlementVault.Payout[] memory payouts) {
        uint256 n = 2;
        if (d.returnReserve > 0) n = 3;
        payouts = new ISettlementVault.Payout[](n);
        payouts[0] = ISettlementVault.Payout({to: d.courier, amount: d.courierAsk});
        payouts[1] = ISettlementVault.Payout({to: config.treasury(), amount: d.protocolFee});
        if (d.returnReserve > 0) {
            payouts[2] = ISettlementVault.Payout({to: d.customer, amount: d.returnReserve});
        }
    }

    /**
     * @dev A return pays the courier's return fee only when the return was
     *      actually confirmed (sec. 17). On a timed-out return the customer is made
     *      whole instead.
     */
    function _settleReturn(uint256 deliveryId, Delivery storage d, bool returnConfirmed) internal {
        uint256 total = customerFundingAmount(deliveryId);
        ISettlementVault.Payout[] memory payouts;

        if (returnConfirmed && d.returnReserve > 0) {
            payouts = new ISettlementVault.Payout[](2);
            payouts[0] = ISettlementVault.Payout({to: d.courier, amount: d.returnReserve});
            payouts[1] = ISettlementVault.Payout({to: d.customer, amount: total - d.returnReserve});
        } else {
            payouts = new ISettlementVault.Payout[](1);
            payouts[0] = ISettlementVault.Payout({to: d.customer, amount: total});
        }

        _releaseCourierCollateral(d);
        _finish(deliveryId, d, State.Returned);
        emit Settled(deliveryId, State.Returned);
        vault.releaseLock(escrowLockId(deliveryId), payouts);
    }

    /**
     * @dev Refunds whichever side funded and releases the other's commitment
     *      (sec. 10). The delivery is moved to its terminal state before any
     *      external call, so the accounting is already final when the registry
     *      and the vault are told about it.
     */
    function _cancelWithRefunds(uint256 deliveryId, Delivery storage d) internal {
        bool hadEscrow = d.customerFunded;
        bool releaseCoverage = d.courierFunded;
        address courier = d.courier;
        uint96 coverage = d.requiredCollateral;

        bool releaseBid = !releaseCoverage && courier != address(0) && _bids[deliveryId][courier].active;
        if (releaseBid) _bids[deliveryId][courier].active = false;

        _finish(deliveryId, d, State.Cancelled);
        emit Settled(deliveryId, State.Cancelled);

        if (releaseCoverage) {
            registry.releaseCollateral(courier, coverage);
        } else if (releaseBid) {
            registry.releaseCollateral(courier, bidDeposit);
        }
        if (hadEscrow) vault.refundLock(escrowLockId(deliveryId));
    }

    function _releaseCourierCollateral(Delivery storage d) internal {
        if (d.courierFunded) registry.releaseCollateral(d.courier, d.requiredCollateral);
    }

    // --------------------------------------------------------------------
    // Internals
    // --------------------------------------------------------------------

    function _transition(uint256 deliveryId, Delivery storage d, State to, uint32 window) internal {
        State from = d.state;
        uint64 deadline = SafeCast.toUint64(block.timestamp) + window;
        d.state = to;
        d.stateDeadline = deadline;
        emit StateChanged(deliveryId, from, to, deadline);
    }

    /// @dev Invariant sec. 33-6: a terminal state carries no deadline and can never move.
    function _finish(uint256 deliveryId, Delivery storage d, State terminal) internal {
        State from = d.state;
        d.state = terminal;
        d.stateDeadline = 0;
        if (activeListings[d.customer] > 0) activeListings[d.customer] -= 1;
        emit StateChanged(deliveryId, from, terminal, 0);
    }

    function _requireDelivery(uint256 deliveryId) internal view returns (Delivery storage d) {
        d = _deliveries[deliveryId];
        if (d.state == State.None) revert UnknownDelivery(deliveryId);
    }

    function _requireState(uint256 deliveryId, Delivery storage d, State expected) internal view {
        if (d.state != expected) revert WrongState(deliveryId, d.state, expected);
    }

    // --------------------------------------------------------------------
    // Views
    // --------------------------------------------------------------------

    function escrowLockId(uint256 deliveryId) public view returns (bytes32) {
        return keccak256(abi.encodePacked("MONOSFER_DELIVERY_ESCROW", address(this), deliveryId));
    }

    function deliveryOf(uint256 deliveryId) external view returns (Delivery memory) {
        return _deliveries[deliveryId];
    }

    function bidOf(uint256 deliveryId, address courier) external view returns (Bid memory) {
        return _bids[deliveryId][courier];
    }

    function isTerminal(uint256 deliveryId) external view returns (bool) {
        return _deliveries[deliveryId].state >= FIRST_TERMINAL;
    }
}
