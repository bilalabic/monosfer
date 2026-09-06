// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProtocolAccessManager} from "../../src/v1/access/ProtocolAccessManager.sol";
import {ProtocolConfig} from "../../src/v1/config/ProtocolConfig.sol";
import {BaselineParams} from "../../src/v1/config/BaselineParams.sol";
import {SettlementVault} from "../../src/v1/vault/SettlementVault.sol";
import {CourierRegistry} from "../../src/v1/registry/CourierRegistry.sol";
import {DeliveryHub} from "../../src/v1/hub/DeliveryHub.sol";
import {CoverageQuote} from "../../src/v1/risk/CoverageQuote.sol";
import {RiskQuoteVerifier} from "../../src/v1/risk/RiskQuoteVerifier.sol";
import {PickupProof} from "../../src/v1/proof/PickupProof.sol";
import {PickupProofVerifier} from "../../src/v1/proof/PickupProofVerifier.sol";
import {QuoteFixture} from "./helpers/QuoteFixture.sol";
import {PickupFixture} from "./helpers/PickupFixture.sol";

contract DeliveryHubTest is QuoteFixture, PickupFixture {
    ProtocolAccessManager internal manager;
    ProtocolConfig internal config;
    SettlementVault internal vault;
    CourierRegistry internal registry;
    DeliveryHub internal hub;

    address internal admin = address(0xA11CE);
    address internal emergency = address(0xE4E4);
    address internal verifier = address(0x7E71F1);
    address internal treasury = address(0x7EA5);

    /// @dev Key-derived: the sender signs the pickup acceptance (sec. 12).
    address internal customer;
    address internal courier = address(0xC0DE);
    address internal courier2 = address(0xC0DE2);
    address internal stranger = address(0xBAD);

    uint96 internal constant BID_DEPOSIT = 1 ether;
    uint96 internal constant COLLATERAL = 5 ether; // R1 (%25) of DECLARED_VALUE
    uint96 internal constant DECLARED_VALUE = 20 ether;
    uint96 internal constant ASK = 10 ether;
    uint96 internal constant RETURN_ASK = 2 ether;

    uint256 internal DEPOSIT;

    function setUp() public {
        customer = senderAddress(0);

        manager = new ProtocolAccessManager(3 days, admin);
        config = new ProtocolConfig(
            manager, 2 days, BaselineParams.baseline(), treasury, quoteSignerAddress(), address(0x2)
        );
        vault = new SettlementVault(manager);
        registry = new CourierRegistry(manager, config, vault);
        hub = new DeliveryHub(manager, config, registry, vault, BID_DEPOSIT);

        vm.startPrank(admin);
        manager.grantRole(manager.EMERGENCY_ROLE(), emergency);
        manager.grantRole(manager.VERIFIER_ROLE(), verifier);
        manager.grantRole(manager.VAULT_CONTROLLER_ROLE(), address(registry));
        manager.grantRole(manager.VAULT_CONTROLLER_ROLE(), address(hub));
        manager.grantRole(manager.REGISTRY_CONTROLLER_ROLE(), address(hub));
        vm.stopPrank();

        DEPOSIT = config.courierBaseDeposit();

        vm.deal(customer, 1_000 ether);
        vm.deal(courier, 1_000 ether);
        vm.deal(courier2, 1_000 ether);

        vm.prank(courier);
        registry.depositStake{value: DEPOSIT + 20 ether}();
        vm.prank(courier2);
        registry.depositStake{value: DEPOSIT + 20 ether}();
    }

    // ------------------------------------------------------------ helpers

    function _create() internal returns (uint256 id) {
        return _createFor(customer, 1);
    }

    function _createFor(address who, uint8 tier) internal returns (uint256 id) {
        CoverageQuote.Quote memory q = buildQuote(config, who, tier, DECLARED_VALUE);
        bytes memory sig = signQuote(hub, q);
        vm.prank(who);
        id = hub.createDelivery(q, sig);
    }

    function _bid(uint256 id, address who) internal returns (uint32 version) {
        vm.prank(who);
        hub.placeBid(id, ASK, RETURN_ASK, 30, uint64(block.timestamp + 1 hours));
        return hub.bidOf(id, who).termsVersion;
    }

    /// @dev The terms version is read before `vm.prank`; a view call placed after
    ///      the cheatcode would consume the prank instead of the call under test.
    function _select(uint256 id, address who) internal {
        uint32 version = hub.bidOf(id, who).termsVersion;
        vm.prank(customer);
        hub.selectCourier(id, who, version);
    }

    function _fundBoth(uint256 id) internal {
        uint256 amount = hub.customerFundingAmount(id);
        vm.prank(customer);
        hub.fundAsCustomer{value: amount}(id);
        vm.prank(courier);
        hub.fundAsCourier(id);
    }

    /**
     * @dev Builds and signs the sender's acceptance. Kept separate from the call
     *      so tests can prepare the arguments before arming `vm.expectRevert` or
     *      `vm.prank`; signing reads the domain separator from the hub, and a
     *      view call placed after a cheatcode would consume it.
     */
    function _acceptance(uint256 id, address forCourier)
        internal
        returns (PickupProof.Acceptance memory acceptance, bytes memory signature)
    {
        acceptance = buildAcceptance(id, forCourier);
        signature = signAcceptance(hub, acceptance, senderKey(0));
    }

    /// @notice The authorised pickup: courier sends, sender's signature authorises.
    function _pickup(uint256 id) internal {
        (PickupProof.Acceptance memory a, bytes memory sig) = _acceptance(id, courier);
        vm.prank(courier);
        hub.confirmPickup(id, a, sig);
    }

    function _toReadyForPickup() internal returns (uint256 id) {
        id = _create();
        _bid(id, courier);
        _select(id, courier);
        _fundBoth(id);
    }

    // ------------------------------------------- [PoC-A]: no stranded funds

    /**
     * @dev The legacy failure: a delivery nobody bids on escrowed the budget with
     *      no way out. Here creation takes no payment at all, so the class of bug
     *      cannot occur — the vault never holds anything for an unbid delivery.
     */
    function test_CreationEscrowsNothing() public {
        uint256 id = _create();
        assertEq(address(vault).balance, (DEPOSIT + 20 ether) * 2, "only courier stake is held");
        assertEq(vault.lockAmount(hub.escrowLockId(id)), 0, "no escrow before selection");
    }

    /// @dev A delivery nobody bids on expires cleanly and frees the listing slot.
    function test_UnbidDeliveryExpiresWithNothingStranded() public {
        uint256 id = _create();
        assertEq(hub.activeListings(customer), 1);

        vm.warp(block.timestamp + config.biddingWindow() + 1);
        hub.poke(id); // anyone

        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.Expired));
        assertEq(hub.activeListings(customer), 0, "listing slot released");
        assertEq(vault.lockAmount(hub.escrowLockId(id)), 0);
    }

    /// @dev The customer funded, the courier never did: the customer gets it back.
    function test_OneSidedFundingRefundsTheFundedSide() public {
        uint256 id = _create();
        _bid(id, courier);
        _select(id, courier);

        uint256 amount = hub.customerFundingAmount(id);
        vm.prank(customer);
        hub.fundAsCustomer{value: amount}(id);

        vm.warp(block.timestamp + config.fundingWindow() + 1);
        hub.poke(id);

        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.Cancelled));
        assertEq(vault.claimableOf(customer), amount, "customer must be refunded in full");
        assertEq(registry.courierOf(courier).reserved, 0, "courier bid reservation released");
    }

    /// @dev The courier funded, the customer never did: the courier's collateral is freed.
    function test_CourierOnlyFundingReleasesCollateral() public {
        uint256 id = _create();
        _bid(id, courier);
        _select(id, courier);

        vm.prank(courier);
        hub.fundAsCourier(id);
        assertEq(registry.courierOf(courier).reserved, COLLATERAL);

        vm.warp(block.timestamp + config.fundingWindow() + 1);
        hub.poke(id);

        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.Cancelled));
        assertEq(registry.courierOf(courier).reserved, 0, "collateral must be released");
    }

    /// @dev Courier never picks up: escrow returns to the customer.
    function test_NoShowCourierRefundsCustomer() public {
        uint256 id = _toReadyForPickup();
        uint256 amount = hub.customerFundingAmount(id);

        vm.warp(block.timestamp + config.pickupWindow() + 1);
        hub.poke(id);

        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.Cancelled));
        assertEq(vault.claimableOf(customer), amount);
        assertEq(registry.courierOf(courier).reserved, 0);
    }

    /**
     * @dev Every non-terminal state must reach a terminal state through timeouts
     *      alone, with no cooperation from either party. This walks the longest
     *      such chain: in transit -> return required -> returned.
     */
    function test_EveryStalledStateReachesTerminalByTimeoutAlone() public {
        uint256 id = _toReadyForPickup();
        _pickup(id);
        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.InTransit));

        vm.warp(block.timestamp + config.transitWindow() + 1);
        hub.poke(id);
        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.ReturnRequired));

        vm.warp(block.timestamp + config.returnWindow() + 1);
        hub.poke(id);

        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.Returned));
        assertEq(vault.claimableOf(customer), hub.customerFundingAmount(id), "customer made whole on a failed return");
        assertEq(registry.courierOf(courier).reserved, 0);
        assertEq(registry.courierOf(courier).activeCustody, 0, "custody released");
        assertGe(address(vault).balance, vault.totalLiabilities());
    }

    // --------------------------------------- [PoC-C]: self-dealing blocked

    /// @dev Invariant sec. 33-16, blocked at both the bid and the selection.
    function test_CustomerCannotBidOnOwnDelivery() public {
        vm.deal(customer, 1_000 ether);
        vm.prank(customer);
        registry.depositStake{value: DEPOSIT}();

        uint256 id = _create();
        vm.expectRevert(DeliveryHub.SelfDealing.selector);
        vm.prank(customer);
        hub.placeBid(id, ASK, RETURN_ASK, 30, uint64(block.timestamp + 1 hours));
    }

    function test_CustomerCannotSelectThemselves() public {
        uint256 id = _create();
        _bid(id, courier);

        vm.expectRevert(DeliveryHub.SelfDealing.selector);
        vm.prank(customer);
        hub.selectCourier(id, customer, 1);
    }

    // ------------------------------------------------------------ bidding

    function test_Bid_CanBeUpdatedAndVersionAdvances() public {
        uint256 id = _create();
        uint32 v1 = _bid(id, courier);

        vm.prank(courier);
        hub.placeBid(id, ASK - 1 ether, RETURN_ASK, 25, uint64(block.timestamp + 2 hours));
        DeliveryHub.Bid memory b = hub.bidOf(id, courier);

        assertEq(b.termsVersion, v1 + 1, "version must advance on update");
        assertEq(b.courierAsk, ASK - 1 ether);
        // Updating must not stack a second reservation.
        assertEq(registry.courierOf(courier).reserved, BID_DEPOSIT, "one reservation per bidder");
    }

    /// @dev The customer commits to the exact version they saw (sec. 7 immutable terms).
    function test_Select_RejectsStaleTermsVersion() public {
        uint256 id = _create();
        uint32 v1 = _bid(id, courier);

        vm.prank(courier);
        hub.placeBid(id, ASK * 2, RETURN_ASK, 25, uint64(block.timestamp + 2 hours));

        vm.expectRevert(abi.encodeWithSelector(DeliveryHub.TermsVersionMismatch.selector, v1, v1 + 1));
        vm.prank(customer);
        hub.selectCourier(id, courier, v1);
    }

    function test_Bid_WithdrawReleasesReservation() public {
        uint256 id = _create();
        _bid(id, courier);
        assertEq(registry.courierOf(courier).reserved, BID_DEPOSIT);

        vm.prank(courier);
        hub.withdrawBid(id);
        assertEq(registry.courierOf(courier).reserved, 0);
        assertFalse(hub.bidOf(id, courier).active);
    }

    /// @dev Losing couriers free their own collateral; selection never loops.
    function test_LosingBidderReleasesOwnReservation() public {
        uint256 id = _create();
        _bid(id, courier);
        _bid(id, courier2);
        _select(id, courier);

        assertEq(registry.courierOf(courier2).reserved, BID_DEPOSIT, "still held until withdrawn");
        vm.prank(courier2);
        hub.withdrawBid(id);
        assertEq(registry.courierOf(courier2).reserved, 0);
    }

    function test_Bid_RejectsExpiredValidUntil() public {
        uint256 id = _create();
        vm.expectRevert(abi.encodeWithSelector(DeliveryHub.BidExpired.selector, uint64(block.timestamp)));
        vm.prank(courier);
        hub.placeBid(id, ASK, RETURN_ASK, 30, uint64(block.timestamp));
    }

    function test_Select_RejectsExpiredBid() public {
        uint256 id = _create();
        _bid(id, courier);
        vm.warp(block.timestamp + 2 hours);

        vm.expectRevert();
        vm.prank(customer);
        hub.selectCourier(id, courier, 1);
    }

    function test_Bid_RequiresEligibility() public {
        uint256 id = _create();
        vm.expectRevert(abi.encodeWithSelector(DeliveryHub.CourierNotEligible.selector, stranger, uint8(1)));
        vm.prank(stranger);
        hub.placeBid(id, ASK, RETURN_ASK, 30, uint64(block.timestamp + 1 hours));
    }

    /// @dev sec. 48: a customer may hold at most 5 open listings.
    function test_ActiveListingCapEnforced() public {
        uint32 limit = config.customerMaxActiveListings();
        for (uint32 i = 0; i < limit; i++) {
            _create();
        }
        CoverageQuote.Quote memory q = buildQuote(config, customer, 1, DECLARED_VALUE);
        bytes memory sig = signQuote(hub, q);
        vm.expectRevert(abi.encodeWithSelector(DeliveryHub.TooManyActiveListings.selector, limit));
        vm.prank(customer);
        hub.createDelivery(q, sig);
    }

    // ------------------------------------------------------------ funding

    /// @dev Invariant sec. 33-17: the escrow must match the selected terms exactly.
    function test_Funding_RejectsWrongAmount() public {
        uint256 id = _create();
        _bid(id, courier);
        _select(id, courier);
        uint256 expected = hub.customerFundingAmount(id);

        vm.expectRevert(abi.encodeWithSelector(DeliveryHub.IncorrectFundingAmount.selector, expected, expected - 1));
        vm.prank(customer);
        hub.fundAsCustomer{value: expected - 1}(id);

        vm.expectRevert(abi.encodeWithSelector(DeliveryHub.IncorrectFundingAmount.selector, expected, expected + 1));
        vm.prank(customer);
        hub.fundAsCustomer{value: expected + 1}(id);
    }

    function test_Funding_AmountIsAskPlusFeePlusReturnReserve() public {
        uint256 id = _create();
        _bid(id, courier);
        _select(id, courier);

        uint256 fee = (uint256(ASK) * config.protocolFeeBps()) / 10_000;
        assertEq(hub.customerFundingAmount(id), uint256(ASK) + fee + RETURN_ASK);
    }

    function test_Funding_BothSidesMoveToReadyForPickup() public {
        uint256 id = _toReadyForPickup();
        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.ReadyForPickup));
    }

    function test_Funding_OneSideDoesNotAdvanceState() public {
        uint256 id = _create();
        _bid(id, courier);
        _select(id, courier);

        uint256 amount = hub.customerFundingAmount(id);
        vm.prank(customer);
        hub.fundAsCustomer{value: amount}(id);
        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.AwaitingFunding));
    }

    /// @dev sec. 8.3 additional bond: a short courier can top up and fund at once.
    function test_Funding_CourierCanTopUpWhileFunding() public {
        vm.deal(courier2, 1_000 ether);
        uint256 id = _create();
        vm.prank(courier2);
        hub.placeBid(id, ASK, RETURN_ASK, 30, uint64(block.timestamp + 1 hours));
        uint32 v = hub.bidOf(id, courier2).termsVersion;
        vm.prank(customer);
        hub.selectCourier(id, courier2, v);

        uint256 stakeBefore = registry.courierOf(courier2).stake;
        vm.prank(courier2);
        hub.fundAsCourier{value: 3 ether}(id);

        assertEq(registry.courierOf(courier2).stake, stakeBefore + 3 ether, "top-up credited");
        assertEq(registry.courierOf(courier2).reserved, COLLATERAL);
    }

    // ------------------------------------------------------- happy path

    function test_HappyPath_SettlesPerBaseline() public {
        uint256 id = _toReadyForPickup();

        _pickup(id);
        assertEq(registry.courierOf(courier).activeCustody, 1);

        vm.prank(courier);
        hub.submitDeliveryProof(id);
        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.DeliveredPending));
        assertEq(registry.courierOf(courier).activeCustody, 0);

        vm.prank(customer);
        hub.confirmDelivery(id);

        // sec. 18.1: ask to courier, fee to treasury, unused return reserve to customer.
        uint256 fee = (uint256(ASK) * config.protocolFeeBps()) / 10_000;
        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.Completed));
        assertEq(vault.claimableOf(courier), ASK);
        assertEq(vault.claimableOf(treasury), fee);
        assertEq(vault.claimableOf(customer), RETURN_ASK, "unused return reserve returns to customer");
        assertEq(registry.courierOf(courier).reserved, 0, "coverage released");
        assertEq(hub.activeListings(customer), 0);
        assertGe(address(vault).balance, vault.totalLiabilities());
    }

    /// @dev sec. 16: after the window anyone may finalize, not just the customer.
    function test_ChallengeWindow_PermissionlessFinalizer() public {
        uint256 id = _toReadyForPickup();
        _pickup(id);
        vm.prank(courier);
        hub.submitDeliveryProof(id);

        vm.warp(block.timestamp + config.challengeWindow() + 1);
        vm.prank(stranger);
        hub.poke(id);

        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.Completed));
        assertEq(vault.claimableOf(courier), ASK);
    }

    /// @dev sec. 17: a confirmed return pays the return fee; the rest goes back.
    function test_ConfirmedReturn_PaysReturnFee() public {
        uint256 id = _toReadyForPickup();
        _pickup(id);
        vm.prank(courier);
        hub.requestReturn(id);
        vm.prank(courier);
        hub.confirmReturn(id);

        uint256 total = hub.customerFundingAmount(id);
        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.Returned));
        assertEq(vault.claimableOf(courier), RETURN_ASK, "return fee paid on a valid return");
        assertEq(vault.claimableOf(customer), total - RETURN_ASK);
        assertEq(registry.courierOf(courier).activeCustody, 0);
    }

    // ------------------------------------------------- state machine rules

    /// @dev Invariant sec. 33-2 / sec. 33-6: a settled delivery can never move again.
    function test_TerminalStateCannotReopen() public {
        uint256 id = _toReadyForPickup();
        _pickup(id);
        vm.prank(courier);
        hub.submitDeliveryProof(id);
        vm.prank(customer);
        hub.confirmDelivery(id);

        assertTrue(hub.isTerminal(id));

        vm.expectRevert();
        vm.prank(customer);
        hub.confirmDelivery(id);

        vm.warp(block.timestamp + 365 days);
        vm.expectRevert();
        hub.poke(id);

        (PickupProof.Acceptance memory a, bytes memory sig) = _acceptance(id, courier);
        vm.expectRevert();
        vm.prank(courier);
        hub.confirmPickup(id, a, sig);
    }

    function test_Poke_RejectsBeforeDeadline() public {
        uint256 id = _create();
        uint64 deadline = hub.deliveryOf(id).stateDeadline;
        vm.expectRevert(abi.encodeWithSelector(DeliveryHub.DeadlineNotReached.selector, deadline));
        hub.poke(id);
    }

    function test_Pickup_OnlySelectedCourier() public {
        uint256 id = _toReadyForPickup();
        (PickupProof.Acceptance memory a, bytes memory sig) = _acceptance(id, courier);
        vm.expectRevert(abi.encodeWithSelector(DeliveryHub.NotCourier.selector, stranger));
        vm.prank(stranger);
        hub.confirmPickup(id, a, sig);
    }

    function test_IllegalTransitionsRevert() public {
        uint256 id = _create();

        // Cannot pick up before funding.
        (PickupProof.Acceptance memory a, bytes memory sig) = _acceptance(id, courier);
        vm.expectRevert();
        vm.prank(courier);
        hub.confirmPickup(id, a, sig);

        // Cannot fund before selection.
        vm.expectRevert();
        vm.prank(customer);
        hub.fundAsCustomer{value: 1 ether}(id);

        // Cannot confirm delivery from Bidding.
        vm.expectRevert();
        vm.prank(customer);
        hub.confirmDelivery(id);
    }

    function test_UnknownDeliveryReverts() public {
        vm.expectRevert(abi.encodeWithSelector(DeliveryHub.UnknownDelivery.selector, uint256(999)));
        hub.poke(999);
    }

    function test_CancelDuringBidding() public {
        uint256 id = _create();
        vm.prank(customer);
        hub.cancelDuringBidding(id);
        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.Cancelled));
        assertEq(hub.activeListings(customer), 0);
    }

    // ---------------------------------------------------------------- pause

    function test_Pause_BlocksNewWorkButPokeStillExits() public {
        uint256 id = _create();
        vm.prank(emergency);
        manager.pause();

        CoverageQuote.Quote memory q = buildQuote(config, customer, 1, DECLARED_VALUE);
        bytes memory sig = signQuote(hub, q);
        vm.expectRevert(ProtocolAccessManager.EnforcedPause.selector);
        vm.prank(customer);
        hub.createDelivery(q, sig);

        // A stalled delivery can still be driven to a terminal state while paused.
        vm.warp(block.timestamp + config.biddingWindow() + 1);
        hub.poke(id);
        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.Expired));
    }

    // ----------------------------------------------------------------- fuzz

    function testFuzz_FundingMustMatchExactly(uint96 sent) public {
        uint256 id = _create();
        _bid(id, courier);
        _select(id, courier);
        uint256 expected = hub.customerFundingAmount(id);
        vm.assume(sent != expected);

        vm.deal(customer, uint256(sent) + 1 ether);
        vm.expectRevert(abi.encodeWithSelector(DeliveryHub.IncorrectFundingAmount.selector, expected, sent));
        vm.prank(customer);
        hub.fundAsCustomer{value: sent}(id);
    }

    function testFuzz_NobodyButCustomerCanSelect(address caller) public {
        vm.assume(caller != customer);
        uint256 id = _create();
        _bid(id, courier);

        vm.expectRevert();
        vm.prank(caller);
        hub.selectCourier(id, courier, 1);
        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.Bidding));
    }
}
