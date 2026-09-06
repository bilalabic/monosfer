// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProtocolAccessManager} from "../../src/v1/access/ProtocolAccessManager.sol";
import {ProtocolConfig} from "../../src/v1/config/ProtocolConfig.sol";
import {BaselineParams} from "../../src/v1/config/BaselineParams.sol";
import {SettlementVault} from "../../src/v1/vault/SettlementVault.sol";
import {ISettlementVault} from "../../src/v1/interfaces/ISettlementVault.sol";
import {CourierRegistry} from "../../src/v1/registry/CourierRegistry.sol";

contract CourierRegistryTest is Test {
    ProtocolAccessManager internal manager;
    ProtocolConfig internal config;
    SettlementVault internal vault;
    CourierRegistry internal registry;

    address internal admin = address(0xA11CE);
    address internal configAdmin = address(0xC0FFEE);
    address internal emergency = address(0xE4E4);
    address internal verifier = address(0x7E71F1);
    address internal hub = address(0x40B); // stands in for DeliveryHub

    address internal courier = address(0xC0DE);
    address internal other = address(0x07E2);
    address internal stranger = address(0xBAD);

    uint256 internal DEPOSIT;
    uint32 internal COOLDOWN;

    function setUp() public {
        manager = new ProtocolAccessManager(3 days, admin);
        config = new ProtocolConfig(
            manager, 2 days, BaselineParams.baseline(), address(0x7EA5), address(0x0001), address(0x0002)
        );
        vault = new SettlementVault(manager);
        registry = new CourierRegistry(manager, config, vault);

        vm.startPrank(admin);
        manager.grantRole(manager.CONFIG_ADMIN_ROLE(), configAdmin);
        manager.grantRole(manager.EMERGENCY_ROLE(), emergency);
        manager.grantRole(manager.VERIFIER_ROLE(), verifier);
        manager.grantRole(manager.REGISTRY_CONTROLLER_ROLE(), hub);
        // The registry moves courier stake inside the vault, so it is a vault controller.
        manager.grantRole(manager.VAULT_CONTROLLER_ROLE(), address(registry));
        vm.stopPrank();

        DEPOSIT = config.courierBaseDeposit();
        COOLDOWN = config.courierWithdrawalCooldown();

        vm.deal(courier, 1_000 ether);
        vm.deal(other, 1_000 ether);
    }

    function _stake(address who, uint256 amount) internal {
        vm.prank(who);
        registry.depositStake{value: amount}();
    }

    // ---------------------------------------------------------------- stake

    function test_Deposit_ActivatesAtBaseDeposit() public {
        _stake(courier, DEPOSIT);

        CourierRegistry.Courier memory c = registry.courierOf(courier);
        assertEq(uint8(c.level), uint8(CourierRegistry.VerificationLevel.C0), "base deposit must grant C0");
        assertEq(c.stake, DEPOSIT);
        assertEq(registry.availableStake(courier), DEPOSIT);
        // Value is held by the vault, never by the registry.
        assertEq(address(vault).balance, DEPOSIT);
        assertEq(address(registry).balance, 0, "registry must never hold value");
    }

    function test_Deposit_BelowMinimumDoesNotActivate() public {
        _stake(courier, DEPOSIT - 1);
        CourierRegistry.Courier memory c = registry.courierOf(courier);
        assertEq(uint8(c.level), uint8(CourierRegistry.VerificationLevel.None));
    }

    function test_Deposit_TopUpUsesSameLock() public {
        _stake(courier, DEPOSIT);
        _stake(courier, 5 ether);
        assertEq(registry.courierOf(courier).stake, DEPOSIT + 5 ether);
        assertEq(vault.lockAmount(registry.stakeLockId(courier)), DEPOSIT + 5 ether);
    }

    function test_Deposit_RejectsZero() public {
        vm.expectRevert(CourierRegistry.ZeroAmount.selector);
        vm.prank(courier);
        registry.depositStake{value: 0}();
    }

    // --------------------------------------------------- the [PoC-B] fix

    /**
     * @dev Legacy `Delivera` has no withdrawStake at all. This is the direct
     *      counter-test: a courier with nothing reserved and nothing in hand
     *      gets their entire stake back.
     */
    function test_CourierCanAlwaysFullyExit() public {
        _stake(courier, DEPOSIT);

        vm.prank(courier);
        registry.deregister();

        vm.warp(block.timestamp + COOLDOWN);
        vm.prank(courier);
        uint256 amount = registry.executeWithdrawal();
        assertEq(amount, DEPOSIT);

        uint256 before = courier.balance;
        vm.prank(courier);
        vault.claim();

        assertEq(courier.balance, before + DEPOSIT, "courier must recover the whole stake");
        assertEq(registry.courierOf(courier).stake, 0);
        assertEq(uint8(registry.courierOf(courier).level), uint8(CourierRegistry.VerificationLevel.None));
        assertGe(address(vault).balance, vault.totalLiabilities());
    }

    /// @dev A courier sitting exactly at the minimum must still be able to leave.
    function test_ExitWorksAtExactlyTheMinimumStake() public {
        _stake(courier, DEPOSIT);
        vm.prank(courier);
        registry.requestWithdrawal(DEPOSIT);
        vm.warp(block.timestamp + COOLDOWN);
        vm.prank(courier);
        registry.executeWithdrawal();
        assertEq(registry.courierOf(courier).stake, 0);
    }

    function test_Withdraw_RequiresCooldown() public {
        _stake(courier, DEPOSIT);
        vm.prank(courier);
        registry.requestWithdrawal(1 ether);

        uint64 readyAt = registry.courierOf(courier).withdrawalReadyAt;
        vm.warp(readyAt - 1);
        vm.expectRevert(abi.encodeWithSelector(CourierRegistry.CooldownNotElapsed.selector, readyAt));
        vm.prank(courier);
        registry.executeWithdrawal();

        vm.warp(readyAt);
        vm.prank(courier);
        registry.executeWithdrawal();
        assertEq(registry.courierOf(courier).stake, DEPOSIT - 1 ether);
    }

    /// @dev The cooldown must come from ProtocolConfig, not a hardcoded constant.
    function test_Withdraw_CooldownComesFromConfig() public {
        _stake(courier, DEPOSIT);
        vm.prank(courier);
        registry.requestWithdrawal(1 ether);
        assertEq(
            registry.courierOf(courier).withdrawalReadyAt,
            uint64(block.timestamp) + config.courierWithdrawalCooldown(),
            "cooldown must track config"
        );
    }

    function test_Withdraw_CanBeCancelled() public {
        _stake(courier, DEPOSIT);
        vm.prank(courier);
        registry.requestWithdrawal(4 ether);
        assertEq(registry.availableStake(courier), DEPOSIT - 4 ether);

        vm.prank(courier);
        registry.cancelWithdrawal();
        assertEq(registry.availableStake(courier), DEPOSIT, "cancelling must return the earmark");
    }

    function test_Withdraw_OnlyOnePendingAtATime() public {
        _stake(courier, DEPOSIT);
        vm.prank(courier);
        registry.requestWithdrawal(1 ether);

        vm.expectRevert(abi.encodeWithSelector(CourierRegistry.WithdrawalAlreadyPending.selector, courier));
        vm.prank(courier);
        registry.requestWithdrawal(1 ether);
    }

    function test_Withdraw_CannotExceedAvailable() public {
        _stake(courier, DEPOSIT);
        vm.expectRevert(
            abi.encodeWithSelector(CourierRegistry.InsufficientAvailableStake.selector, DEPOSIT + 1, DEPOSIT)
        );
        vm.prank(courier);
        registry.requestWithdrawal(DEPOSIT + 1);
    }

    /**
     * @dev Two registries sharing one vault must not derive the same stake lock id.
     *      Under the immutable-and-redeploy strategy a replacement registry runs
     *      alongside the old one, and a colliding id would make the new registry
     *      unable to ever open a lock.
     */
    function test_StakeLockId_IsPerRegistry() public {
        CourierRegistry second = new CourierRegistry(manager, config, vault);
        assertTrue(
            registry.stakeLockId(courier) != second.stakeLockId(courier),
            "lock ids must differ across registry deployments"
        );

        // Role id read before the cheatcode, or the view call consumes the prank.
        bytes32 vaultControllerRole = manager.VAULT_CONTROLLER_ROLE();
        vm.prank(admin);
        manager.grantRole(vaultControllerRole, address(second));

        _stake(courier, DEPOSIT);
        vm.prank(courier);
        second.depositStake{value: DEPOSIT}();

        assertEq(vault.lockAmount(registry.stakeLockId(courier)), DEPOSIT);
        assertEq(vault.lockAmount(second.stakeLockId(courier)), DEPOSIT);
    }

    // ----------------------------------------------------------- collateral

    /// @dev Invariant §33-4: the same stake cannot back two deliveries.
    function test_Collateral_CannotBeReservedTwice() public {
        _stake(courier, DEPOSIT);

        vm.prank(hub);
        registry.reserveCollateral(courier, DEPOSIT);
        assertEq(registry.availableStake(courier), 0);

        vm.expectRevert(abi.encodeWithSelector(CourierRegistry.InsufficientAvailableStake.selector, 1, 0));
        vm.prank(hub);
        registry.reserveCollateral(courier, 1);
    }

    /// @dev Reserved collateral must not be withdrawable.
    function test_Collateral_ReservedIsNotWithdrawable() public {
        _stake(courier, DEPOSIT);
        vm.prank(hub);
        registry.reserveCollateral(courier, 6 ether);

        uint256 available = DEPOSIT - 6 ether;
        vm.expectRevert(
            abi.encodeWithSelector(CourierRegistry.InsufficientAvailableStake.selector, available + 1, available)
        );
        vm.prank(courier);
        registry.requestWithdrawal(available + 1);
    }

    /// @dev A pending withdrawal must not double as collateral while it waits.
    function test_PendingWithdrawalCannotBackADelivery() public {
        _stake(courier, DEPOSIT);
        vm.prank(courier);
        registry.requestWithdrawal(DEPOSIT);

        vm.expectRevert(abi.encodeWithSelector(CourierRegistry.InsufficientAvailableStake.selector, 1, 0));
        vm.prank(hub);
        registry.reserveCollateral(courier, 1);
    }

    function test_Collateral_ReleaseRestoresAvailability() public {
        _stake(courier, DEPOSIT);
        vm.prank(hub);
        registry.reserveCollateral(courier, 6 ether);
        vm.prank(hub);
        registry.releaseCollateral(courier, 6 ether);
        assertEq(registry.availableStake(courier), DEPOSIT);
    }

    function test_Collateral_SlashMovesValueToBeneficiary() public {
        _stake(courier, DEPOSIT);
        vm.prank(hub);
        registry.reserveCollateral(courier, 4 ether);

        vm.prank(hub);
        registry.slashCollateral(courier, 4 ether, other);

        assertEq(vault.claimableOf(other), 4 ether, "beneficiary must be credited");
        assertEq(registry.courierOf(courier).stake, DEPOSIT - 4 ether);
        assertEq(registry.courierOf(courier).reserved, 0);
        // Falling below the base deposit deactivates the courier.
        assertEq(uint8(registry.courierOf(courier).level), uint8(CourierRegistry.VerificationLevel.None));
        assertGe(address(vault).balance, vault.totalLiabilities());
    }

    function test_Collateral_OnlyController() public {
        _stake(courier, DEPOSIT);
        vm.expectRevert();
        vm.prank(stranger);
        registry.reserveCollateral(courier, 1 ether);
    }

    // -------------------------------------------------------------- custody

    /// @dev Invariant §33-10: MAX_ACTIVE_CUSTODY cannot be exceeded.
    function test_Custody_LimitEnforced() public {
        _stake(courier, DEPOSIT);
        uint32 limit = config.maxActiveCustody();

        for (uint32 i = 0; i < limit; i++) {
            vm.prank(hub);
            registry.openCustody(courier);
        }
        assertEq(registry.courierOf(courier).activeCustody, limit);

        vm.expectRevert(abi.encodeWithSelector(CourierRegistry.CustodyLimitReached.selector, limit));
        vm.prank(hub);
        registry.openCustody(courier);
    }

    function test_Custody_CloseFreesASlot() public {
        _stake(courier, DEPOSIT);
        vm.prank(hub);
        registry.openCustody(courier);
        vm.prank(hub);
        registry.closeCustody(courier);
        assertEq(registry.courierOf(courier).activeCustody, 0);

        vm.prank(hub);
        registry.openCustody(courier);
        assertEq(registry.courierOf(courier).activeCustody, 1);
    }

    function test_Custody_CannotCloseWhenNoneOpen() public {
        _stake(courier, DEPOSIT);
        vm.expectRevert(abi.encodeWithSelector(CourierRegistry.NoActiveCustody.selector, courier));
        vm.prank(hub);
        registry.closeCustody(courier);
    }

    /// @dev A courier physically holding a package cannot walk away from it.
    function test_Deregister_BlockedWhileHoldingAPackage() public {
        _stake(courier, DEPOSIT);
        vm.prank(hub);
        registry.openCustody(courier);

        vm.expectRevert(abi.encodeWithSelector(CourierRegistry.HasActiveCustody.selector, uint32(1)));
        vm.prank(courier);
        registry.deregister();
    }

    function test_Deregister_BlockedWithReservedCollateral() public {
        _stake(courier, DEPOSIT);
        vm.prank(hub);
        registry.reserveCollateral(courier, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(CourierRegistry.HasReservedCollateral.selector, 1 ether));
        vm.prank(courier);
        registry.deregister();
    }

    // --------------------------------------------------------- verification

    function test_Verification_OnlyVerifierCanPromote() public {
        _stake(courier, DEPOSIT);
        vm.expectRevert();
        vm.prank(stranger);
        registry.setVerificationLevel(courier, CourierRegistry.VerificationLevel.C2);

        vm.prank(verifier);
        registry.setVerificationLevel(courier, CourierRegistry.VerificationLevel.C2);
        assertEq(uint8(registry.courierOf(courier).level), uint8(CourierRegistry.VerificationLevel.C2));
    }

    /// @dev §24/§3.3: a verification level can never stand in for collateral.
    function test_Verification_RequiresBaseDeposit() public {
        vm.expectRevert(abi.encodeWithSelector(CourierRegistry.StakeBelowMinimum.selector, 0, DEPOSIT));
        vm.prank(verifier);
        registry.setVerificationLevel(courier, CourierRegistry.VerificationLevel.C2);
    }

    /// @dev §6 tier gating: R1 needs C0+, R2 needs C1+, R3 needs C2, R4 disabled.
    function test_Eligibility_MatchesRiskTiers() public {
        _stake(courier, DEPOSIT);

        assertTrue(registry.isEligibleFor(courier, 1), "C0 must reach R1");
        assertFalse(registry.isEligibleFor(courier, 2), "C0 must not reach R2");
        assertFalse(registry.isEligibleFor(courier, 3));

        vm.prank(verifier);
        registry.setVerificationLevel(courier, CourierRegistry.VerificationLevel.C1);
        assertTrue(registry.isEligibleFor(courier, 2), "C1 must reach R2");
        assertFalse(registry.isEligibleFor(courier, 3), "C1 must not reach R3");

        vm.prank(verifier);
        registry.setVerificationLevel(courier, CourierRegistry.VerificationLevel.C2);
        assertTrue(registry.isEligibleFor(courier, 3), "C2 must reach R3");

        assertFalse(registry.isEligibleFor(courier, 4), "R4 stays disabled");
        assertFalse(registry.isEligibleFor(courier, 0));
    }

    function test_Suspension_BlocksEligibilityAndReservation() public {
        _stake(courier, DEPOSIT);
        vm.prank(verifier);
        registry.setSuspended(courier, true);

        assertFalse(registry.isEligibleFor(courier, 1), "suspended courier must not be eligible");

        vm.expectRevert(abi.encodeWithSelector(CourierRegistry.CourierSuspended.selector, courier));
        vm.prank(hub);
        registry.reserveCollateral(courier, 1 ether);

        vm.prank(verifier);
        registry.setSuspended(courier, false);
        assertTrue(registry.isEligibleFor(courier, 1));
    }

    /// @dev A courier already at the custody limit is not eligible for more work.
    function test_Eligibility_FalseWhileHoldingAPackage() public {
        _stake(courier, DEPOSIT);
        vm.prank(hub);
        registry.openCustody(courier);
        assertFalse(registry.isEligibleFor(courier, 1), "at custody limit, not eligible");
    }

    // ---------------------------------------------------------------- pause

    /// @dev §45: new stake stops during pause, but leaving must stay possible.
    function test_Pause_BlocksDepositButAllowsExit() public {
        _stake(courier, DEPOSIT);

        vm.prank(emergency);
        manager.pause();

        vm.expectRevert(ProtocolAccessManager.EnforcedPause.selector);
        vm.prank(courier);
        registry.depositStake{value: 1 ether}();

        // Exit path stays open end to end.
        vm.prank(courier);
        registry.requestWithdrawal(DEPOSIT);
        vm.warp(block.timestamp + COOLDOWN);
        vm.prank(courier);
        registry.executeWithdrawal();
        vm.prank(courier);
        vault.claim();
        assertEq(registry.courierOf(courier).stake, 0, "courier must be able to leave a paused protocol");
    }

    // ----------------------------------------------------------------- fuzz

    function testFuzz_StakeSplitAlwaysHolds(uint96 deposit, uint96 reserve, uint96 withdraw) public {
        deposit = uint96(bound(deposit, DEPOSIT, 500 ether));
        _stake(courier, deposit);

        reserve = uint96(bound(reserve, 0, deposit));
        if (reserve > 0) {
            vm.prank(hub);
            registry.reserveCollateral(courier, reserve);
        }

        uint256 available = uint256(deposit) - reserve;
        withdraw = uint96(bound(withdraw, 0, available));
        if (withdraw > 0) {
            vm.prank(courier);
            registry.requestWithdrawal(withdraw);
        }

        CourierRegistry.Courier memory c = registry.courierOf(courier);
        assertEq(
            uint256(c.stake),
            registry.availableStake(courier) + c.reserved + c.pendingWithdrawal,
            "stake = available + reserved + pending"
        );
        assertLe(uint256(c.reserved) + c.pendingWithdrawal, c.stake, "commitments cannot exceed stake");
        assertGe(address(vault).balance, vault.totalLiabilities(), "vault stays solvent");
    }

    function testFuzz_OnlyControllerCanReserve(address caller) public {
        vm.assume(caller != hub);
        _stake(courier, DEPOSIT);
        vm.expectRevert();
        vm.prank(caller);
        registry.reserveCollateral(courier, 1 ether);
        assertEq(registry.courierOf(courier).reserved, 0);
    }
}
