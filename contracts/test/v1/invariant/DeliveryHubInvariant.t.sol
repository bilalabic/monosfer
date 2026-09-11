// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {ProtocolAccessManager} from "../../../src/v1/access/ProtocolAccessManager.sol";
import {ProtocolConfig} from "../../../src/v1/config/ProtocolConfig.sol";
import {BaselineParams} from "../../../src/v1/config/BaselineParams.sol";
import {SettlementVault} from "../../../src/v1/vault/SettlementVault.sol";
import {CourierRegistry} from "../../../src/v1/registry/CourierRegistry.sol";
import {DeliveryHub} from "../../../src/v1/hub/DeliveryHub.sol";
import {ReputationRegistry} from "../../../src/v1/reputation/ReputationRegistry.sol";
import {CoverageQuote} from "../../../src/v1/risk/CoverageQuote.sol";
import {DeliveryProof} from "../../../src/v1/proof/DeliveryProof.sol";
import {PickupProof} from "../../../src/v1/proof/PickupProof.sol";
import {QuoteFixture} from "../helpers/QuoteFixture.sol";
import {PickupFixture} from "../helpers/PickupFixture.sol";
import {PodFixture} from "../helpers/PodFixture.sol";

/**
 * @notice Drives DeliveryHub through random lifecycles from random callers,
 *         interleaved with time jumps and pokes.
 * @dev Reverts are swallowed. The point is that no ordering of calls, authorised
 *      or not, can break the invariants asserted by the test contract.
 */
contract HubHandler is QuoteFixture, PickupFixture, PodFixture {
    DeliveryHub public immutable hub;
    CourierRegistry public immutable registry;
    ProtocolConfig public immutable config;
    SettlementVault public immutable vault;

    address[] public customers;
    address[] public couriers;
    uint256[] public deliveries;

    mapping(uint256 => PickupProof.Acceptance) internal lastAcceptance;
    mapping(uint256 => bytes) internal lastSignature;
    mapping(uint256 => bool) internal hasAcceptance;
    /// @dev Nonces this sender has already spent, so reuse can be attacked.
    mapping(address => uint256[]) internal spentNonces;

    uint256 public created;
    uint256 public forgedAccepted;
    uint256 public pickedUp;
    uint256 public forgedPickupAccepted;
    uint256 public replayedPickupAccepted;
    uint256 public replayAttempts;
    uint256 public courierFunded;
    uint256 public forgeAttempts;
    uint256 public proved;
    uint256 public forgedProofAttempts;
    uint256 public forgedProofAccepted;
    uint256 public selected;
    uint256 public funded;
    uint256 public settled;

    constructor(DeliveryHub hub_, CourierRegistry registry_, ProtocolConfig config_, SettlementVault vault_) {
        hub = hub_;
        registry = registry_;
        config = config_;
        vault = vault_;

        // Key-derived: customers sign pickup acceptances (sec. 12).
        customers.push(senderAddress(0));
        customers.push(senderAddress(1));
        couriers.push(address(0xC0DE01));
        couriers.push(address(0xC0DE02));
        couriers.push(address(0xC0DE03));
    }

    function _customer(uint256 s) internal view returns (address) {
        return customers[s % customers.length];
    }

    function _customerKey(address who) internal pure returns (uint256) {
        return who == senderAddress(0) ? senderKey(0) : senderKey(1);
    }

    function _courier(uint256 s) internal view returns (address) {
        return couriers[s % couriers.length];
    }

    function _delivery(uint256 s) internal view returns (uint256, bool) {
        if (deliveries.length == 0) return (0, false);
        return (deliveries[s % deliveries.length], true);
    }

    /**
     * @dev Quotes are signed with the configured risk key so the authorised path
     *      stays reachable. `createDeliveryForged` below exercises rejection.
     */
    function createDelivery(uint256 custSeed, uint8 tier, uint96 declaredValue) external {
        tier = uint8(bound(tier, 1, 3));
        declaredValue = uint96(bound(declaredValue, 1 ether, 40 ether));
        address cust = _customer(custSeed);

        CoverageQuote.Quote memory q = buildQuote(config, cust, tier, declaredValue);
        bytes memory sig = signQuote(hub, q);
        vm.prank(cust);
        try hub.createDelivery(q, sig) returns (uint256 id) {
            deliveries.push(id);
            created++;
        } catch {}
    }

    /// @notice A quote signed by the wrong key must never open a delivery.
    function createDeliveryForged(uint256 custSeed, uint8 tier, uint96 declaredValue, uint256 wrongKey) external {
        tier = uint8(bound(tier, 1, 3));
        declaredValue = uint96(bound(declaredValue, 1 ether, 40 ether));
        wrongKey = bound(wrongKey, 1, type(uint128).max);
        if (wrongKey == QUOTE_SIGNER_KEY) return;
        address cust = _customer(custSeed);

        CoverageQuote.Quote memory q = buildQuote(config, cust, tier, declaredValue);
        bytes memory sig = signQuoteAs(hub, q, wrongKey);
        vm.prank(cust);
        try hub.createDelivery(q, sig) returns (uint256 id) {
            deliveries.push(id);
            forgedAccepted++;
        } catch {}
    }

    function placeBid(uint256 dSeed, uint256 cSeed, uint96 ask) external {
        (uint256 id, bool ok) = _delivery(dSeed);
        if (!ok) return;
        ask = uint96(bound(ask, 1 ether, 20 ether));
        vm.prank(_courier(cSeed));
        try hub.placeBid(id, ask, 1 ether, 30, uint64(block.timestamp + 2 hours)) {} catch {}
    }

    function withdrawBid(uint256 dSeed, uint256 cSeed) external {
        (uint256 id, bool ok) = _delivery(dSeed);
        if (!ok) return;
        vm.prank(_courier(cSeed));
        try hub.withdrawBid(id) {} catch {}
    }

    function selectCourier(uint256 dSeed, uint256 cSeed) external {
        (uint256 id, bool ok) = _delivery(dSeed);
        if (!ok) return;
        address c = _courier(cSeed);
        uint32 version = hub.bidOf(id, c).termsVersion;
        vm.prank(hub.deliveryOf(id).customer);
        try hub.selectCourier(id, c, version) {
            selected++;
        } catch {}
    }

    function fundCustomer(uint256 dSeed) external {
        (uint256 id, bool ok) = _delivery(dSeed);
        if (!ok) return;
        DeliveryHub.Delivery memory d = hub.deliveryOf(id);
        uint256 amount = hub.customerFundingAmount(id);
        vm.deal(d.customer, amount + 1 ether);
        vm.prank(d.customer);
        try hub.fundAsCustomer{value: amount}(id) {
            funded++;
        } catch {}
    }

    function fundCourier(uint256 dSeed, uint96 topUp) external {
        (uint256 id, bool ok) = _delivery(dSeed);
        if (!ok) return;
        DeliveryHub.Delivery memory d = hub.deliveryOf(id);
        if (d.courier == address(0)) return;
        topUp = uint96(bound(topUp, 0, 5 ether));
        vm.deal(d.courier, uint256(topUp) + 1 ether);
        vm.prank(d.courier);
        try hub.fundAsCourier{value: topUp}(id) {
            courierFunded++;
        } catch {}
    }

    /**
     * @dev Assembles one delivery all the way to `ReadyForPickup` in a single
     *      action.
     *
     *      Random sequences essentially never line up create -> bid -> select ->
     *      fund -> fund on the same delivery, so without this the campaign never
     *      produced a delivery the pickup handlers could act on, and every
     *      invariant past `Bidding` held vacuously. Mutation-testing the six
     *      sec. 12 checks confirmed it: unit tests failed, invariants did not
     *      move. This gives the fuzzer live pickup-stage deliveries to attack.
     *
     *      Every step still goes through the real entry points with real
     *      authorisation; nothing here bypasses a check.
     */
    function bootstrapReadyForPickup(uint256 custSeed, uint256 cSeed, uint8 tier, uint96 declaredValue) external {
        tier = uint8(bound(tier, 1, 3));
        declaredValue = uint96(bound(declaredValue, 1 ether, 20 ether));
        address cust = _customer(custSeed);
        address cour = _courier(cSeed);

        CoverageQuote.Quote memory q = buildQuote(config, cust, tier, declaredValue);
        bytes memory qsig = signQuote(hub, q);
        vm.prank(cust);
        uint256 id;
        try hub.createDelivery(q, qsig) returns (uint256 newId) {
            id = newId;
            deliveries.push(id);
            created++;
        } catch {
            return;
        }

        vm.prank(cour);
        try hub.placeBid(id, 2 ether, 1 ether, 30, uint64(block.timestamp + 2 hours)) {}
        catch {
            return;
        }

        uint32 version = hub.bidOf(id, cour).termsVersion;
        vm.prank(cust);
        try hub.selectCourier(id, cour, version) {
            selected++;
        } catch {
            return;
        }

        uint256 amount = hub.customerFundingAmount(id);
        vm.deal(cust, amount + 1 ether);
        vm.prank(cust);
        try hub.fundAsCustomer{value: amount}(id) {
            funded++;
        } catch {
            return;
        }

        // No public view for the bond due, and none is needed: any surplus is
        // deposited to the courier's stake rather than lost, so overshooting is
        // safe and keeps the funding step from failing on arithmetic.
        uint256 topUp = 20 ether;
        vm.deal(cour, topUp + 1 ether);
        vm.prank(cour);
        try hub.fundAsCourier{value: topUp}(id) {
            courierFunded++;
        } catch {}
    }

    /**
     * @dev Signs with the delivery's real sender so the authorised path stays
     *      reachable. `pickupForged` below exercises rejection, and
     *      `pickupReplay` re-submits a spent acceptance.
     */
    function pickup(uint256 dSeed) external {
        (uint256 id, bool ok) = _delivery(dSeed);
        if (!ok) return;
        DeliveryHub.Delivery memory d = hub.deliveryOf(id);
        if (d.courier == address(0)) return;

        PickupProof.Acceptance memory a = buildAcceptance(id, d.courier);
        bytes memory sig = signAcceptance(hub, a, _customerKey(d.customer));

        vm.prank(d.courier);
        try hub.confirmPickup(id, a, sig) {
            lastAcceptance[id] = a;
            lastSignature[id] = sig;
            hasAcceptance[id] = true;
            spentNonces[d.customer].push(a.nonce);
            pickedUp++;
        } catch {}
    }

    /// @dev A pickup authorised by a key that is not the sender's must never pass.
    function pickupForged(uint256 dSeed, uint256 wrongKey) external {
        (uint256 id, bool ok) = _delivery(dSeed);
        if (!ok) return;
        DeliveryHub.Delivery memory d = hub.deliveryOf(id);
        if (d.courier == address(0)) return;

        wrongKey = bound(wrongKey, 1, type(uint128).max);
        if (wrongKey == senderKey(0) || wrongKey == senderKey(1)) return;

        // A distinct tag: sharing the authorised attempt's nonce would make this
        // fail on the nonce check instead of on the signature, which is the check
        // it exists to exercise.
        PickupProof.Acceptance memory a = buildAcceptanceWithExpiry(id, d.courier, uint64(block.timestamp) + 1 hours, 1);
        bytes memory sig = signAcceptance(hub, a, wrongKey);

        forgeAttempts++;
        vm.prank(d.courier);
        try hub.confirmPickup(id, a, sig) {
            forgedPickupAccepted++;
        } catch {}
    }

    /**
     * @dev Invariant sec. 33-7. Resubmitting the identical acceptance is stopped
     *      by the state machine long before the nonce is looked at, so it proves
     *      nothing about the nonce guard. The attack that actually reaches it is
     *      this one: take a nonce the sender has already spent, build a *fresh,
     *      correctly signed* acceptance for a delivery still awaiting pickup, and
     *      submit that. Every other check passes; only the burned nonce stands in
     *      the way.
     */
    function pickupNonceReuse(uint256 dSeed, uint256 nSeed) external {
        (uint256 id, bool ok) = _delivery(dSeed);
        if (!ok) return;
        DeliveryHub.Delivery memory d = hub.deliveryOf(id);
        if (d.courier == address(0)) return;

        uint256[] storage spent = spentNonces[d.customer];
        if (spent.length == 0) return;

        PickupProof.Acceptance memory a = buildAcceptance(id, d.courier);
        a.nonce = spent[nSeed % spent.length];
        bytes memory sig = signAcceptance(hub, a, _customerKey(d.customer));

        replayAttempts++;
        vm.prank(d.courier);
        try hub.confirmPickup(id, a, sig) {
            replayedPickupAccepted++;
        } catch {}
    }

    function deliverProof(uint256 dSeed) external {
        (uint256 id, bool ok) = _delivery(dSeed);
        if (!ok) return;
        DeliveryHub.Delivery memory d = hub.deliveryOf(id);
        if (d.courier == address(0)) return;

        DeliveryProof.Attestation memory a = buildAttestation(config, id, d.courier);
        bytes memory sig = signAttestation(hub, a);

        vm.prank(d.courier);
        try hub.submitDeliveryProof(id, a, sig) {
            proved++;
        } catch {}
    }

    /// @dev An attestation the configured service never signed must never pass.
    function deliverProofForged(uint256 dSeed, uint256 wrongKey) external {
        (uint256 id, bool ok) = _delivery(dSeed);
        if (!ok) return;
        DeliveryHub.Delivery memory d = hub.deliveryOf(id);
        if (d.courier == address(0)) return;

        wrongKey = bound(wrongKey, 1, type(uint128).max);
        if (wrongKey == POD_SIGNER_KEY) return;

        DeliveryProof.Attestation memory a = buildAttestationFull(
            id,
            d.courier,
            DeliveryProof.POD_OTP,
            uint64(block.timestamp),
            uint64(block.timestamp) + config.podAttestationValidity(),
            1
        );
        bytes memory sig = signAttestationAs(hub, a, wrongKey);

        forgedProofAttempts++;
        vm.prank(d.courier);
        try hub.submitDeliveryProof(id, a, sig) {
            forgedProofAccepted++;
        } catch {}
    }

    function confirmDelivery(uint256 dSeed) external {
        (uint256 id, bool ok) = _delivery(dSeed);
        if (!ok) return;
        vm.prank(hub.deliveryOf(id).customer);
        try hub.confirmDelivery(id) {
            settled++;
        } catch {}
    }

    function requestReturn(uint256 dSeed, uint256 who) external {
        (uint256 id, bool ok) = _delivery(dSeed);
        if (!ok) return;
        DeliveryHub.Delivery memory d = hub.deliveryOf(id);
        vm.prank(who % 2 == 0 ? d.customer : d.courier);
        try hub.requestReturn(id) {} catch {}
    }

    function confirmReturn(uint256 dSeed) external {
        (uint256 id, bool ok) = _delivery(dSeed);
        if (!ok) return;
        vm.prank(hub.deliveryOf(id).courier);
        try hub.confirmReturn(id) {} catch {}
    }

    /// @dev Anyone may poke; the fuzzer uses a random address on purpose.
    function poke(uint256 dSeed, uint32 warpBy) external {
        vm.warp(block.timestamp + (warpBy % 5 days));
        (uint256 id, bool ok) = _delivery(dSeed);
        if (!ok) return;
        vm.prank(address(uint160(uint256(keccak256(abi.encode(dSeed))))));
        try hub.poke(id) {} catch {}
    }

    function deliveryCount() external view returns (uint256) {
        return deliveries.length;
    }

    function customerCount() external view returns (uint256) {
        return customers.length;
    }
}

contract DeliveryHubInvariantTest is StdInvariant, QuoteFixture, PodFixture {
    ProtocolAccessManager internal manager;
    ProtocolConfig internal config;
    SettlementVault internal vault;
    CourierRegistry internal registry;
    DeliveryHub internal hub;
    ReputationRegistry internal reputation;
    HubHandler internal handler;

    address internal admin = address(0xA11CE);
    address internal treasury = address(0x7EA5);

    function setUp() public {
        manager = new ProtocolAccessManager(3 days, admin);
        config = new ProtocolConfig(
            manager, 2 days, BaselineParams.baseline(), treasury, quoteSignerAddress(), podSignerAddress()
        );
        vault = new SettlementVault(manager);
        registry = new CourierRegistry(manager, config, vault);
        reputation = new ReputationRegistry(manager);
        hub = new DeliveryHub(manager, config, registry, vault, reputation, 1 ether);

        vm.startPrank(admin);
        manager.grantRole(manager.VAULT_CONTROLLER_ROLE(), address(registry));
        manager.grantRole(manager.VAULT_CONTROLLER_ROLE(), address(hub));
        manager.grantRole(manager.REGISTRY_CONTROLLER_ROLE(), address(hub));
        manager.grantRole(manager.REPUTATION_REPORTER_ROLE(), address(hub));
        manager.grantRole(manager.VERIFIER_ROLE(), address(this));
        vm.stopPrank();

        handler = new HubHandler(hub, registry, config, vault);

        // Stake the couriers so the authorised paths are reachable.
        // The amount is read before vm.prank: a view call after the cheatcode
        // consumes the prank and the stake would land on the test contract.
        uint256 stakeAmount = config.courierBaseDeposit() + 40 ether;
        for (uint256 i = 0; i < 3; i++) {
            address c = handler.couriers(i);
            vm.deal(c, 200 ether);
            vm.prank(c);
            registry.depositStake{value: stakeAmount}();
        }

        // Verify them to C2. Stake alone caps a courier at C1, which is only
        // eligible for tier-1 deliveries; without this the fuzzer can never bid
        // on the tier-2 and tier-3 deliveries it generates, selection never
        // happens, and every invariant past `Bidding` holds vacuously.
        for (uint256 i = 0; i < 3; i++) {
            registry.setVerificationLevel(handler.couriers(i), CourierRegistry.VerificationLevel.C2);
        }

        targetContract(address(handler));
    }

    /**
     * @dev The property this phase exists for. Every live delivery carries a
     *      deadline, so it can always be driven to a terminal state by anyone.
     *      A live state with no deadline would be a delivery whose escrow nobody
     *      can free — the legacy failure.
     */
    function invariant_EveryLiveDeliveryHasADeadline() public view {
        uint256 n = handler.deliveryCount();
        for (uint256 i = 0; i < n; i++) {
            uint256 id = handler.deliveries(i);
            DeliveryHub.Delivery memory d = hub.deliveryOf(id);
            if (!hub.isTerminal(id)) {
                assertGt(d.stateDeadline, 0, "live delivery without a deadline has no exit");
            } else {
                assertEq(d.stateDeadline, 0, "terminal delivery must carry no deadline");
            }
        }
    }

    /// @dev Invariant sec. 33-16: the customer can never end up as their own courier.
    function invariant_CustomerIsNeverTheCourier() public view {
        uint256 n = handler.deliveryCount();
        for (uint256 i = 0; i < n; i++) {
            DeliveryHub.Delivery memory d = hub.deliveryOf(handler.deliveries(i));
            if (d.courier != address(0)) {
                assertTrue(d.courier != d.customer, "self-dealing delivery exists");
            }
        }
    }

    /// @dev Invariant sec. 33-1: the protocol-wide solvency law survives the lifecycle.
    function invariant_VaultStaysSolvent() public view {
        assertGe(address(vault).balance, vault.totalLiabilities(), "vault insolvent");
    }

    /// @dev Commitments can never exceed a courier's stake, mid-delivery included.
    function invariant_CourierCommitmentsWithinStake() public view {
        for (uint256 i = 0; i < 3; i++) {
            CourierRegistry.Courier memory k = registry.courierOf(handler.couriers(i));
            assertLe(uint256(k.reserved) + k.pendingWithdrawal, k.stake, "commitments exceed stake");
            assertLe(k.activeCustody, config.maxActiveCustody(), "custody limit exceeded");
        }
    }

    /// @dev Active listings must equal the number of live deliveries per customer.
    function invariant_ActiveListingsMatchLiveDeliveries() public view {
        uint256 nc = handler.customerCount();
        uint256 nd = handler.deliveryCount();
        for (uint256 c = 0; c < nc; c++) {
            address cust = handler.customers(c);
            uint256 live;
            for (uint256 i = 0; i < nd; i++) {
                uint256 id = handler.deliveries(i);
                if (hub.deliveryOf(id).customer == cust && !hub.isTerminal(id)) live++;
            }
            assertEq(uint256(hub.activeListings(cust)), live, "listing count drifted from live deliveries");
        }
    }

    /// @dev A settled escrow lock can never hold value again (sec. 33-2).
    function invariant_SettledEscrowNeverHoldsValue() public view {
        uint256 n = handler.deliveryCount();
        for (uint256 i = 0; i < n; i++) {
            uint256 id = handler.deliveries(i);
            if (hub.isTerminal(id)) {
                assertEq(vault.lockAmount(hub.escrowLockId(id)), 0, "terminal delivery still holds escrow");
            }
        }
    }

    /**
     * @dev The strongest form of "no state without an exit": take whatever the
     *      fuzzer produced, jump far into the future and poke repeatedly. Every
     *      delivery must end terminal, with no cooperation from any party.
     */
    function invariant_AllDeliveriesCanBeDrivenTerminal() public {
        uint256 n = handler.deliveryCount();
        if (n == 0) return;

        uint256 snapshot = vm.snapshotState();
        // Each poke advances one state; the longest live chain is five hops.
        // Absolute timestamps, not `block.timestamp + delta`: inside an invariant
        // function the reads did not reflect earlier warps, so a relative step
        // silently stopped advancing after the first round.
        uint256 t = block.timestamp;
        for (uint256 round = 0; round < 8; round++) {
            t += 31 days;
            vm.warp(t);
            for (uint256 i = 0; i < n; i++) {
                try hub.poke(handler.deliveries(i)) {} catch {}
            }
        }
        for (uint256 i = 0; i < n; i++) {
            uint256 id = handler.deliveries(i);
            assertTrue(hub.isTerminal(id), "delivery could not be driven to a terminal state");
            assertEq(vault.lockAmount(hub.escrowLockId(id)), 0, "escrow still locked after settlement");
        }
        assertGe(address(vault).balance, vault.totalLiabilities(), "vault insolvent after forced settlement");
        vm.revertToState(snapshot);
    }

    /// @dev Invariant sec. 33-8: a forged quote can never open a delivery.
    function invariant_ForgedQuoteNeverAccepted() public view {
        assertEq(handler.forgedAccepted(), 0, "a delivery was opened with a forged coverage quote");
    }

    /// @dev Invariant sec. 33-7: a pickup acceptance can be spent exactly once.
    function invariant_PickupAcceptanceNeverReplayed() public view {
        assertEq(handler.replayedPickupAccepted(), 0, "a pickup was accepted on an already-spent nonce");
    }

    /// @dev sec. 12: only the sender's own signature authorises a handover.
    function invariant_ForgedPickupNeverAccepted() public view {
        assertEq(handler.forgedPickupAccepted(), 0, "a pickup was accepted on a signature the sender never made");
    }

    /// @dev sec. 15: only the configured attestation service can prove delivery.
    function invariant_ForgedPodAttestationNeverAccepted() public view {
        assertEq(handler.forgedProofAccepted(), 0, "a delivery was proven with an attestation the service never signed");
    }

    /// @dev Guards against vacuity: the authorised lifecycle must be reachable.
    function test_invariant_HandlerReachesFullLifecycle() public {
        handler.createDelivery(0, 1, 20 ether);
        assertGt(handler.created(), 0, "creation reachable");

        handler.placeBid(0, 0, 5 ether);
        handler.selectCourier(0, 0);
        assertGt(handler.selected(), 0, "selection reachable");

        handler.fundCustomer(0);
        assertGt(handler.funded(), 0, "funding reachable");
        handler.fundCourier(0, 0);

        handler.pickup(0);
        assertGt(handler.pickedUp(), 0, "signed pickup reachable");

        // The two pickup invariants are "counter stayed at zero" assertions, so
        // they hold trivially unless the adversarial handlers actually run. Both
        // are driven here and their attempt counters checked, which is what makes
        // the zero meaningful rather than merely unreached.
        handler.pickupNonceReuse(0, 0);
        assertGt(handler.replayAttempts(), 0, "nonce-reuse path reachable");
        handler.pickupForged(0, 0xBADBADBAD);
        assertGt(handler.forgeAttempts(), 0, "forged-pickup path reachable");

        handler.deliverProof(0);
        assertGt(handler.proved(), 0, "signed delivery proof reachable");
        handler.deliverProofForged(0, 0xFEEDFACE);
        assertGt(handler.forgedProofAttempts(), 0, "forged-proof path reachable");
        handler.confirmDelivery(0);
        assertGt(handler.settled(), 0, "settlement reachable");
    }
}
