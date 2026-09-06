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

/**
 * @notice Drives DeliveryHub through random lifecycles from random callers,
 *         interleaved with time jumps and pokes.
 * @dev Reverts are swallowed. The point is that no ordering of calls, authorised
 *      or not, can break the invariants asserted by the test contract.
 */
contract HubHandler is Test {
    DeliveryHub public immutable hub;
    CourierRegistry public immutable registry;
    ProtocolConfig public immutable config;
    SettlementVault public immutable vault;

    address[] public customers;
    address[] public couriers;
    uint256[] public deliveries;

    uint256 public created;
    uint256 public selected;
    uint256 public funded;
    uint256 public settled;

    constructor(DeliveryHub hub_, CourierRegistry registry_, ProtocolConfig config_, SettlementVault vault_) {
        hub = hub_;
        registry = registry_;
        config = config_;
        vault = vault_;

        customers.push(address(0xC05701));
        customers.push(address(0xC05702));
        couriers.push(address(0xC0DE01));
        couriers.push(address(0xC0DE02));
        couriers.push(address(0xC0DE03));
    }

    function _customer(uint256 s) internal view returns (address) {
        return customers[s % customers.length];
    }

    function _courier(uint256 s) internal view returns (address) {
        return couriers[s % couriers.length];
    }

    function _delivery(uint256 s) internal view returns (uint256, bool) {
        if (deliveries.length == 0) return (0, false);
        return (deliveries[s % deliveries.length], true);
    }

    function createDelivery(uint256 custSeed, uint8 tier, uint96 collateral) external {
        tier = uint8(bound(tier, 1, 3));
        collateral = uint96(bound(collateral, 1 ether, 5 ether));
        vm.prank(_customer(custSeed));
        try hub.createDelivery(tier, collateral) returns (uint256 id) {
            deliveries.push(id);
            created++;
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
        try hub.fundAsCourier{value: topUp}(id) {} catch {}
    }

    function pickup(uint256 dSeed) external {
        (uint256 id, bool ok) = _delivery(dSeed);
        if (!ok) return;
        vm.prank(hub.deliveryOf(id).courier);
        try hub.confirmPickup(id) {} catch {}
    }

    function deliverProof(uint256 dSeed) external {
        (uint256 id, bool ok) = _delivery(dSeed);
        if (!ok) return;
        vm.prank(hub.deliveryOf(id).courier);
        try hub.submitDeliveryProof(id) {} catch {}
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

contract DeliveryHubInvariantTest is StdInvariant, Test {
    ProtocolAccessManager internal manager;
    ProtocolConfig internal config;
    SettlementVault internal vault;
    CourierRegistry internal registry;
    DeliveryHub internal hub;
    HubHandler internal handler;

    address internal admin = address(0xA11CE);
    address internal treasury = address(0x7EA5);

    function setUp() public {
        manager = new ProtocolAccessManager(3 days, admin);
        config = new ProtocolConfig(manager, 2 days, BaselineParams.baseline(), treasury, address(0x1), address(0x2));
        vault = new SettlementVault(manager);
        registry = new CourierRegistry(manager, config, vault);
        hub = new DeliveryHub(manager, config, registry, vault, 1 ether);

        vm.startPrank(admin);
        manager.grantRole(manager.VAULT_CONTROLLER_ROLE(), address(registry));
        manager.grantRole(manager.VAULT_CONTROLLER_ROLE(), address(hub));
        manager.grantRole(manager.REGISTRY_CONTROLLER_ROLE(), address(hub));
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

    /// @dev Guards against vacuity: the authorised lifecycle must be reachable.
    function test_HandlerReachesFullLifecycle() public {
        handler.createDelivery(0, 1, 2 ether);
        assertGt(handler.created(), 0, "creation reachable");

        handler.placeBid(0, 0, 5 ether);
        handler.selectCourier(0, 0);
        assertGt(handler.selected(), 0, "selection reachable");

        handler.fundCustomer(0);
        assertGt(handler.funded(), 0, "funding reachable");
        handler.fundCourier(0, 0);

        handler.pickup(0);
        handler.deliverProof(0);
        handler.confirmDelivery(0);
        assertGt(handler.settled(), 0, "settlement reachable");
    }
}
