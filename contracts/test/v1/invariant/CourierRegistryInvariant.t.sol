// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {ProtocolAccessManager} from "../../../src/v1/access/ProtocolAccessManager.sol";
import {ProtocolConfig} from "../../../src/v1/config/ProtocolConfig.sol";
import {BaselineParams} from "../../../src/v1/config/BaselineParams.sol";
import {SettlementVault} from "../../../src/v1/vault/SettlementVault.sol";
import {CourierRegistry} from "../../../src/v1/registry/CourierRegistry.sol";

/**
 * @notice Drives CourierRegistry through random staking, reservation, withdrawal
 *         and custody sequences from both authorised and unauthorised callers.
 * @dev Amounts are bounded into legal ranges so the authorised paths are actually
 *      reachable; unauthorised calls are still attempted and expected to revert.
 */
contract RegistryHandler is Test {
    ProtocolAccessManager public immutable manager;
    ProtocolConfig public immutable config;
    SettlementVault public immutable vault;
    CourierRegistry public immutable registry;
    address public immutable hub;
    address public immutable verifier;

    address[] public couriers;

    uint256 public deposits;
    uint256 public reservations;
    uint256 public withdrawalsExecuted;
    uint256 public custodyOpens;

    constructor(
        ProtocolAccessManager manager_,
        ProtocolConfig config_,
        SettlementVault vault_,
        CourierRegistry registry_,
        address hub_,
        address verifier_
    ) {
        manager = manager_;
        config = config_;
        vault = vault_;
        registry = registry_;
        hub = hub_;
        verifier = verifier_;

        couriers.push(address(0xC0DE01));
        couriers.push(address(0xC0DE02));
        couriers.push(address(0xC0DE03));
    }

    function _courier(uint256 seed) internal view returns (address) {
        return couriers[seed % couriers.length];
    }

    function _controller(uint256 seed) internal view returns (address) {
        return seed % 4 == 0 ? address(uint160(uint256(keccak256(abi.encode(seed))))) : hub;
    }

    function deposit(uint256 courierSeed, uint96 amount) external {
        address c = _courier(courierSeed);
        amount = uint96(bound(amount, 0.1 ether, 50 ether));
        vm.deal(c, amount);
        vm.prank(c);
        try registry.depositStake{value: amount}() {
            deposits++;
        } catch {}
    }

    function reserve(uint256 courierSeed, uint256 callerSeed, uint96 amount) external {
        address c = _courier(courierSeed);
        uint256 available = registry.availableStake(c);
        if (available == 0) return;
        amount = uint96(bound(amount, 1, available));
        vm.prank(_controller(callerSeed));
        try registry.reserveCollateral(c, amount) {
            reservations++;
        } catch {}
    }

    function release(uint256 courierSeed, uint256 callerSeed, uint96 amount) external {
        address c = _courier(courierSeed);
        uint256 reserved = registry.courierOf(c).reserved;
        if (reserved == 0) return;
        amount = uint96(bound(amount, 1, reserved));
        vm.prank(_controller(callerSeed));
        try registry.releaseCollateral(c, amount) {} catch {}
    }

    function slash(uint256 courierSeed, uint256 callerSeed, uint96 amount) external {
        address c = _courier(courierSeed);
        uint256 reserved = registry.courierOf(c).reserved;
        if (reserved == 0) return;
        amount = uint96(bound(amount, 1, reserved));
        vm.prank(_controller(callerSeed));
        try registry.slashCollateral(c, amount, address(0xBEEF)) {} catch {}
    }

    function requestWithdraw(uint256 courierSeed, uint96 amount) external {
        address c = _courier(courierSeed);
        uint256 available = registry.availableStake(c);
        if (available == 0) return;
        amount = uint96(bound(amount, 1, available));
        vm.prank(c);
        try registry.requestWithdrawal(amount) {} catch {}
    }

    function executeWithdraw(uint256 courierSeed, uint32 warpBy) external {
        vm.warp(block.timestamp + (warpBy % 3 days));
        address c = _courier(courierSeed);
        vm.prank(c);
        try registry.executeWithdrawal() {
            withdrawalsExecuted++;
        } catch {}
    }

    function cancelWithdraw(uint256 courierSeed) external {
        address c = _courier(courierSeed);
        vm.prank(c);
        try registry.cancelWithdrawal() {} catch {}
    }

    function openCustody(uint256 courierSeed, uint256 callerSeed) external {
        vm.prank(_controller(callerSeed));
        try registry.openCustody(_courier(courierSeed)) {
            custodyOpens++;
        } catch {}
    }

    function closeCustody(uint256 courierSeed, uint256 callerSeed) external {
        vm.prank(_controller(callerSeed));
        try registry.closeCustody(_courier(courierSeed)) {} catch {}
    }

    function setLevel(uint256 courierSeed, uint8 levelSeed) external {
        vm.prank(verifier);
        try registry.setVerificationLevel(
            _courier(courierSeed), CourierRegistry.VerificationLevel(uint8(bound(levelSeed, 0, 3)))
        ) {}
            catch {}
    }

    function courierCount() external view returns (uint256) {
        return couriers.length;
    }
}

contract CourierRegistryInvariantTest is StdInvariant, Test {
    ProtocolAccessManager internal manager;
    ProtocolConfig internal config;
    SettlementVault internal vault;
    CourierRegistry internal registry;
    RegistryHandler internal handler;

    address internal admin = address(0xA11CE);
    address internal hub = address(0x40B);
    address internal verifier = address(0x7E71F1);

    function setUp() public {
        manager = new ProtocolAccessManager(3 days, admin);
        config = new ProtocolConfig(
            manager, 2 days, BaselineParams.baseline(), address(0x7EA5), address(0x0001), address(0x0002)
        );
        vault = new SettlementVault(manager);
        registry = new CourierRegistry(manager, config, vault);

        vm.startPrank(admin);
        manager.grantRole(manager.REGISTRY_CONTROLLER_ROLE(), hub);
        manager.grantRole(manager.VERIFIER_ROLE(), verifier);
        manager.grantRole(manager.VAULT_CONTROLLER_ROLE(), address(registry));
        vm.stopPrank();

        handler = new RegistryHandler(manager, config, vault, registry, hub, verifier);
        targetContract(address(handler));
    }

    /**
     * @dev Invariant sec. 33-4: courier collateral cannot be reused. Commitments —
     *      collateral reserved against deliveries plus any earmarked withdrawal —
     *      can never exceed the stake actually held.
     */
    function invariant_CommitmentsNeverExceedStake() public view {
        uint256 n = handler.courierCount();
        for (uint256 i = 0; i < n; i++) {
            address c = handler.couriers(i);
            CourierRegistry.Courier memory k = registry.courierOf(c);
            assertLe(uint256(k.reserved) + k.pendingWithdrawal, k.stake, "commitments exceed stake");
            assertEq(
                uint256(k.stake),
                registry.availableStake(c) + k.reserved + k.pendingWithdrawal,
                "stake split must balance"
            );
        }
    }

    /// @dev Invariant sec. 33-10: a courier can never hold more than the configured limit.
    function invariant_CustodyLimitNeverExceeded() public view {
        uint32 limit = config.maxActiveCustody();
        uint256 n = handler.courierCount();
        for (uint256 i = 0; i < n; i++) {
            assertLe(registry.courierOf(handler.couriers(i)).activeCustody, limit, "custody limit exceeded");
        }
    }

    /// @dev The registry is pure accounting: it must never hold value itself.
    function invariant_RegistryHoldsNoValue() public view {
        assertEq(address(registry).balance, 0, "registry must never hold value");
    }

    /// @dev Registry totals must agree with the sum of per-courier records.
    function invariant_TotalsMatchPerCourierSums() public view {
        uint256 stakeSum;
        uint256 reservedSum;
        uint256 n = handler.courierCount();
        for (uint256 i = 0; i < n; i++) {
            CourierRegistry.Courier memory k = registry.courierOf(handler.couriers(i));
            stakeSum += k.stake;
            reservedSum += k.reserved;
        }
        assertEq(registry.totalStaked(), stakeSum, "totalStaked drifted from per-courier stakes");
        assertEq(registry.totalReserved(), reservedSum, "totalReserved drifted");
    }

    /// @dev Stake lives in the vault, so the protocol-wide solvency law still holds.
    function invariant_VaultStaysSolvent() public view {
        assertGe(address(vault).balance, vault.totalLiabilities(), "vault insolvent");
    }

    /// @dev Guards against vacuity: the authorised paths must be reachable.
    function test_HandlerReachesStakeAndWithdrawal() public {
        handler.deposit(0, uint96(config.courierBaseDeposit()));
        assertGt(handler.deposits(), 0, "deposit must be reachable");

        handler.reserve(0, 1, 1 ether);
        assertGt(handler.reservations(), 0, "reservation must be reachable");

        handler.openCustody(0, 1);
        assertGt(handler.custodyOpens(), 0, "custody must be reachable");

        handler.release(0, 1, 1 ether);
        handler.requestWithdraw(0, 1 ether);
        handler.executeWithdraw(0, uint32(2 days));
        assertGt(handler.withdrawalsExecuted(), 0, "withdrawal must be reachable");
    }
}
