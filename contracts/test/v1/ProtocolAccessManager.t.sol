// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ProtocolAccessManager} from "../../src/v1/access/ProtocolAccessManager.sol";

/// @notice Consumer standing in for a real protocol contract that honours the pause.
contract MockConsumer {
    ProtocolAccessManager public immutable manager;
    uint256 public counter;

    constructor(ProtocolAccessManager manager_) {
        manager = manager_;
    }

    function doWork() external {
        manager.requireNotPaused();
        counter++;
    }
}

contract ProtocolAccessManagerTest is Test {
    ProtocolAccessManager internal manager;
    MockConsumer internal consumer;

    address internal admin = address(0xA11CE);
    address internal configAdmin = address(0xC0FFEE);
    address internal emergency = address(0xE4E4);
    address internal signerAdmin = address(0x5165);
    address internal treasurer = address(0x7EA5);
    address internal stranger = address(0xBAD);

    uint48 internal constant ADMIN_DELAY = 3 days;

    function setUp() public {
        manager = new ProtocolAccessManager(ADMIN_DELAY, admin);
        consumer = new MockConsumer(manager);

        vm.startPrank(admin);
        manager.grantRole(manager.CONFIG_ADMIN_ROLE(), configAdmin);
        manager.grantRole(manager.EMERGENCY_ROLE(), emergency);
        manager.grantRole(manager.SIGNER_ADMIN_ROLE(), signerAdmin);
        manager.grantRole(manager.TREASURER_ROLE(), treasurer);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------- setup

    function test_Constructor_RejectsShortAdminDelay() public {
        uint48 tooShort = uint48(1 hours);
        vm.expectRevert(
            abi.encodeWithSelector(
                ProtocolAccessManager.AdminTransferDelayTooShort.selector, tooShort, manager.MIN_ADMIN_TRANSFER_DELAY()
            )
        );
        new ProtocolAccessManager(tooShort, admin);
    }

    function test_Constructor_RejectsZeroAdmin() public {
        // OpenZeppelin rejects the zero default admin before our own check runs.
        vm.expectRevert();
        new ProtocolAccessManager(ADMIN_DELAY, address(0));
    }

    function test_RolesAreDistinct() public view {
        bytes32[4] memory roles = [
            manager.CONFIG_ADMIN_ROLE(), manager.EMERGENCY_ROLE(), manager.SIGNER_ADMIN_ROLE(), manager.TREASURER_ROLE()
        ];
        for (uint256 i = 0; i < roles.length; i++) {
            for (uint256 j = i + 1; j < roles.length; j++) {
                assertTrue(roles[i] != roles[j], "role ids must be distinct");
            }
        }
    }

    // ---------------------------------------------------------------- pause

    function test_Pause_OnlyEmergencyRole() public {
        // Role ids are read first: a view call placed after vm.prank/vm.expectRevert
        // would consume the cheatcode instead of the call under test.
        bytes32 role = manager.EMERGENCY_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, role)
        );
        vm.prank(stranger);
        manager.pause();
    }

    function test_Pause_ConfigAdminCannotPause() public {
        vm.prank(configAdmin);
        vm.expectRevert();
        manager.pause();
    }

    function test_Pause_IsImmediate() public {
        vm.prank(emergency);
        manager.pause();
        assertTrue(manager.paused());
    }

    function test_Pause_RevertsWhenAlreadyPaused() public {
        vm.prank(emergency);
        manager.pause();
        vm.prank(emergency);
        vm.expectRevert(ProtocolAccessManager.AlreadyPaused.selector);
        manager.pause();
    }

    /// @dev The whole point of the asymmetry: EMERGENCY can stop, but cannot restart.
    function test_Unpause_EmergencyRoleCannotUnpause() public {
        vm.prank(emergency);
        manager.pause();
        vm.prank(emergency);
        vm.expectRevert();
        manager.scheduleUnpause();
    }

    function test_Unpause_RequiresSchedule() public {
        vm.prank(emergency);
        manager.pause();
        vm.prank(configAdmin);
        vm.expectRevert(ProtocolAccessManager.UnpauseNotScheduled.selector);
        manager.unpause();
    }

    function test_Unpause_RequiresDelayToElapse() public {
        vm.prank(emergency);
        manager.pause();
        vm.prank(configAdmin);
        manager.scheduleUnpause();

        uint64 readyAt = manager.unpauseReadyAt();

        vm.warp(readyAt - 1);
        vm.prank(configAdmin);
        vm.expectRevert(abi.encodeWithSelector(ProtocolAccessManager.UnpauseTooEarly.selector, readyAt));
        manager.unpause();

        vm.warp(readyAt);
        vm.prank(configAdmin);
        manager.unpause();
        assertFalse(manager.paused());
        assertEq(manager.unpauseReadyAt(), 0);
    }

    /// @dev A fresh pause must not inherit an in-flight unpause schedule.
    function test_Pause_ClearsPendingUnpauseSchedule() public {
        vm.prank(emergency);
        manager.pause();
        vm.prank(configAdmin);
        manager.scheduleUnpause();
        uint64 firstReadyAt = manager.unpauseReadyAt();

        vm.warp(firstReadyAt);
        vm.prank(configAdmin);
        manager.unpause();

        // Pause again: the old schedule must not carry over.
        vm.prank(emergency);
        manager.pause();
        assertEq(manager.unpauseReadyAt(), 0, "schedule must be cleared by pause");

        vm.prank(configAdmin);
        vm.expectRevert(ProtocolAccessManager.UnpauseNotScheduled.selector);
        manager.unpause();
    }

    function test_ScheduleUnpause_RevertsWhenNotPaused() public {
        vm.prank(configAdmin);
        vm.expectRevert(ProtocolAccessManager.ExpectedPause.selector);
        manager.scheduleUnpause();
    }

    // ---------------------------------------------------------- integration

    function test_Integration_PausePropagatesToConsumer() public {
        consumer.doWork();
        assertEq(consumer.counter(), 1);

        vm.prank(emergency);
        manager.pause();

        vm.expectRevert(ProtocolAccessManager.EnforcedPause.selector);
        consumer.doWork();
        assertEq(consumer.counter(), 1, "paused work must not take effect");

        vm.prank(configAdmin);
        manager.scheduleUnpause();
        vm.warp(manager.unpauseReadyAt());
        vm.prank(configAdmin);
        manager.unpause();

        consumer.doWork();
        assertEq(consumer.counter(), 2);
    }

    // ---------------------------------------------------------------- roles

    function test_RequireRole_RevertsForNonHolder() public {
        bytes32 role = manager.CONFIG_ADMIN_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, role)
        );
        manager.requireRole(role, stranger);
    }

    function test_RequireRole_PassesForHolder() public view {
        manager.requireRole(manager.CONFIG_ADMIN_ROLE(), configAdmin);
    }

    function test_RequireNotPaused_RevertsWhilePaused() public {
        manager.requireNotPaused();
        vm.prank(emergency);
        manager.pause();
        vm.expectRevert(ProtocolAccessManager.EnforcedPause.selector);
        manager.requireNotPaused();
    }

    /// @dev Invariant sec. 33-15: a role holder must not be able to widen their own authority.
    function test_RoleHolderCannotGrantThemselvesAnotherRole() public {
        bytes32 emergencyRole = manager.EMERGENCY_ROLE();
        bytes32 configRole = manager.CONFIG_ADMIN_ROLE();
        bytes32 treasurerRole = manager.TREASURER_ROLE();

        vm.expectRevert();
        vm.prank(configAdmin);
        manager.grantRole(emergencyRole, configAdmin);

        vm.expectRevert();
        vm.prank(emergency);
        manager.grantRole(configRole, emergency);

        vm.expectRevert();
        vm.prank(signerAdmin);
        manager.grantRole(treasurerRole, signerAdmin);

        // And none of them actually acquired anything.
        assertFalse(manager.hasRole(emergencyRole, configAdmin));
        assertFalse(manager.hasRole(configRole, emergency));
        assertFalse(manager.hasRole(treasurerRole, signerAdmin));
    }

    function test_DefaultAdminTransferIsTwoStepAndDelayed() public {
        address newAdmin = address(0x9E9ADD);
        vm.prank(admin);
        manager.beginDefaultAdminTransfer(newAdmin);

        // Not yet effective.
        assertTrue(manager.hasRole(manager.DEFAULT_ADMIN_ROLE(), admin));
        assertFalse(manager.hasRole(manager.DEFAULT_ADMIN_ROLE(), newAdmin));

        (, uint48 schedule) = manager.pendingDefaultAdmin();
        // OpenZeppelin requires the schedule to be strictly in the past.
        vm.warp(uint256(schedule) + 1);
        vm.prank(newAdmin);
        manager.acceptDefaultAdminTransfer();

        assertTrue(manager.hasRole(manager.DEFAULT_ADMIN_ROLE(), newAdmin));
        assertFalse(manager.hasRole(manager.DEFAULT_ADMIN_ROLE(), admin));
    }

    // ----------------------------------------------------------------- fuzz

    function testFuzz_OnlyEmergencyCanPause(address caller) public {
        vm.assume(caller != emergency);
        vm.expectRevert();
        vm.prank(caller);
        manager.pause();
        assertFalse(manager.paused(), "only EMERGENCY_ROLE may pause");
    }

    function testFuzz_UnpauseNeverEarly(uint64 warpTo) public {
        vm.prank(emergency);
        manager.pause();
        vm.prank(configAdmin);
        manager.scheduleUnpause();
        uint64 readyAt = manager.unpauseReadyAt();
        vm.assume(warpTo < readyAt && warpTo >= block.timestamp);

        vm.warp(warpTo);
        vm.prank(configAdmin);
        vm.expectRevert(abi.encodeWithSelector(ProtocolAccessManager.UnpauseTooEarly.selector, readyAt));
        manager.unpause();
        assertTrue(manager.paused(), "must remain paused before readyAt");
    }
}
