// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProtocolAccessManager} from "../../src/v1/access/ProtocolAccessManager.sol";
import {SettlementVault} from "../../src/v1/vault/SettlementVault.sol";
import {ISettlementVault} from "../../src/v1/interfaces/ISettlementVault.sol";

/// @notice Receiver that always rejects value. Models the legacy [PoC-D] treasury.
contract RevertingReceiver {
    receive() external payable {
        revert("I reject MON");
    }
}

/// @notice Receiver that burns all forwarded gas.
contract GasBurningReceiver {
    uint256 public sink;

    receive() external payable {
        while (true) {
            sink++;
        }
    }
}

/// @notice Attempts to re-enter claim() during payout.
contract ReentrantClaimer {
    SettlementVault public immutable vault;
    bool public attempted;
    bool public reentryReverted;

    constructor(SettlementVault vault_) {
        vault = vault_;
    }

    receive() external payable {
        if (!attempted) {
            attempted = true;
            try vault.claim() {
                reentryReverted = false;
            } catch {
                reentryReverted = true;
            }
        }
    }

    function pull() external {
        vault.claim();
    }
}

contract SettlementVaultTest is Test {
    ProtocolAccessManager internal manager;
    SettlementVault internal vault;

    address internal admin = address(0xA11CE);
    address internal configAdmin = address(0xC0FFEE);
    address internal emergency = address(0xE4E4);
    address internal controller = address(0xC07401);
    address internal stranger = address(0xBAD);

    address internal customer = address(0xC057);
    address internal courier = address(0xC0DE);
    address internal treasury = address(0x7EA5);

    bytes32 internal constant LOCK_A = keccak256("delivery-1");
    bytes32 internal constant LOCK_B = keccak256("delivery-2");

    function setUp() public {
        manager = new ProtocolAccessManager(3 days, admin);
        vm.startPrank(admin);
        manager.grantRole(manager.CONFIG_ADMIN_ROLE(), configAdmin);
        manager.grantRole(manager.EMERGENCY_ROLE(), emergency);
        manager.grantRole(manager.VAULT_CONTROLLER_ROLE(), controller);
        vm.stopPrank();

        vault = new SettlementVault(manager);
        vm.deal(controller, 1_000 ether);
    }

    function _lock(bytes32 id, address owner, uint256 amount) internal {
        vm.prank(controller);
        vault.lock{value: amount}(id, owner);
    }

    function _payouts(address to, uint256 amount) internal pure returns (ISettlementVault.Payout[] memory p) {
        p = new ISettlementVault.Payout[](1);
        p[0] = ISettlementVault.Payout({to: to, amount: amount});
    }

    // ------------------------------------------------------------ custody in

    function test_Lock_RecordsCustody() public {
        _lock(LOCK_A, customer, 1 ether);
        assertEq(vault.lockAmount(LOCK_A), 1 ether);
        assertEq(vault.lockOwner(LOCK_A), customer);
        assertEq(vault.totalLocked(), 1 ether);
        assertEq(address(vault).balance, 1 ether);
    }

    function test_Lock_OnlyController() public {
        vm.deal(stranger, 1 ether);
        vm.expectRevert();
        vm.prank(stranger);
        vault.lock{value: 1 ether}(LOCK_A, customer);
    }

    function test_Lock_RejectsDuplicateId() public {
        _lock(LOCK_A, customer, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(SettlementVault.LockAlreadyExists.selector, LOCK_A));
        vm.prank(controller);
        vault.lock{value: 1 ether}(LOCK_A, customer);
    }

    function test_Lock_RejectsZeroValueAndZeroOwner() public {
        vm.expectRevert(SettlementVault.ZeroAmount.selector);
        vm.prank(controller);
        vault.lock{value: 0}(LOCK_A, customer);

        vm.expectRevert(SettlementVault.ZeroAddress.selector);
        vm.prank(controller);
        vault.lock{value: 1 ether}(LOCK_A, address(0));
    }

    function test_TopUp_IncreasesLock() public {
        _lock(LOCK_A, customer, 1 ether);
        vm.prank(controller);
        vault.topUpLock{value: 0.5 ether}(LOCK_A);
        assertEq(vault.lockAmount(LOCK_A), 1.5 ether);
        assertEq(vault.totalLocked(), 1.5 ether);
    }

    function test_TopUp_RejectsInactiveLock() public {
        vm.expectRevert(abi.encodeWithSelector(SettlementVault.LockNotActive.selector, LOCK_A));
        vm.prank(controller);
        vault.topUpLock{value: 1 ether}(LOCK_A);
    }

    // ----------------------------------------------------------- settlement

    function test_Release_CreditsClaimableWithoutSendingValue() public {
        _lock(LOCK_A, customer, 1 ether);

        ISettlementVault.Payout[] memory p = new ISettlementVault.Payout[](2);
        p[0] = ISettlementVault.Payout({to: courier, amount: 0.98 ether});
        p[1] = ISettlementVault.Payout({to: treasury, amount: 0.02 ether});

        uint256 balanceBefore = address(vault).balance;
        vm.prank(controller);
        vault.releaseLock(LOCK_A, p);

        // No value moved out: settlement is bookkeeping only.
        assertEq(address(vault).balance, balanceBefore, "settlement must not move value");
        assertEq(vault.claimableOf(courier), 0.98 ether);
        assertEq(vault.claimableOf(treasury), 0.02 ether);
        assertEq(vault.totalLocked(), 0);
        assertEq(vault.totalClaimable(), 1 ether);
    }

    /// @dev Invariant §33-3: a short payout would strand the remainder.
    function test_Release_RejectsPayoutMismatch() public {
        _lock(LOCK_A, customer, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(SettlementVault.PayoutMismatch.selector, 1 ether, 0.9 ether));
        vm.prank(controller);
        vault.releaseLock(LOCK_A, _payouts(courier, 0.9 ether));

        vm.expectRevert(abi.encodeWithSelector(SettlementVault.PayoutMismatch.selector, 1 ether, 1.1 ether));
        vm.prank(controller);
        vault.releaseLock(LOCK_A, _payouts(courier, 1.1 ether));
    }

    /// @dev Invariant §33-2: a delivery settles only once.
    function test_Release_CannotSettleTwice() public {
        _lock(LOCK_A, customer, 1 ether);
        vm.prank(controller);
        vault.releaseLock(LOCK_A, _payouts(courier, 1 ether));

        vm.expectRevert(abi.encodeWithSelector(SettlementVault.LockNotActive.selector, LOCK_A));
        vm.prank(controller);
        vault.releaseLock(LOCK_A, _payouts(courier, 1 ether));
    }

    function test_Refund_ReturnsWholeLockToOwner() public {
        _lock(LOCK_A, customer, 1 ether);
        vm.prank(controller);
        vault.refundLock(LOCK_A);

        assertEq(vault.claimableOf(customer), 1 ether);
        assertEq(vault.totalLocked(), 0);
    }

    function test_Release_OnlyController() public {
        _lock(LOCK_A, customer, 1 ether);
        vm.expectRevert();
        vm.prank(stranger);
        vault.releaseLock(LOCK_A, _payouts(courier, 1 ether));
    }

    // ---------------------------------------------------------------- claim

    function test_Claim_PaysAndZeroesBalance() public {
        _lock(LOCK_A, customer, 1 ether);
        vm.prank(controller);
        vault.releaseLock(LOCK_A, _payouts(courier, 1 ether));

        uint256 before = courier.balance;
        vm.prank(courier);
        vault.claim();

        assertEq(courier.balance, before + 1 ether);
        assertEq(vault.claimableOf(courier), 0);
        assertEq(vault.totalClaimable(), 0);
    }

    function test_Claim_RejectsEmptyBalance() public {
        vm.expectRevert(abi.encodeWithSelector(SettlementVault.NothingToClaim.selector, courier));
        vm.prank(courier);
        vault.claim();
    }

    function test_Claim_CannotDoubleClaim() public {
        _lock(LOCK_A, customer, 1 ether);
        vm.prank(controller);
        vault.releaseLock(LOCK_A, _payouts(courier, 1 ether));

        vm.prank(courier);
        vault.claim();

        vm.expectRevert(abi.encodeWithSelector(SettlementVault.NothingToClaim.selector, courier));
        vm.prank(courier);
        vault.claim();
    }

    /// @dev claimFor always pays the account, never the caller.
    function test_ClaimFor_PaysAccountNotCaller() public {
        _lock(LOCK_A, customer, 1 ether);
        vm.prank(controller);
        vault.releaseLock(LOCK_A, _payouts(courier, 1 ether));

        uint256 courierBefore = courier.balance;
        uint256 strangerBefore = stranger.balance;

        vm.prank(stranger);
        vault.claimFor(courier);

        assertEq(courier.balance, courierBefore + 1 ether, "funds must reach the account");
        assertEq(stranger.balance, strangerBefore, "caller must not receive anything");
    }

    // ------------------------------------------- the legacy failure, fixed

    /**
     * @dev Direct answer to gap-analysis [PoC-D]. In the legacy contract a
     *      reverting treasury made confirmDelivery revert permanently, freezing
     *      the courier's payment and the escrow. Here the same receiver is simply
     *      credited, and everyone else settles and withdraws normally.
     */
    function test_RevertingReceiverCannotBlockAnyoneElse() public {
        RevertingReceiver badTreasury = new RevertingReceiver();

        _lock(LOCK_A, customer, 1 ether);
        ISettlementVault.Payout[] memory p = new ISettlementVault.Payout[](2);
        p[0] = ISettlementVault.Payout({to: courier, amount: 0.98 ether});
        p[1] = ISettlementVault.Payout({to: address(badTreasury), amount: 0.02 ether});

        // Settlement succeeds despite one receiver being unable to accept value.
        vm.prank(controller);
        vault.releaseLock(LOCK_A, p);

        // The courier is paid in full.
        uint256 before = courier.balance;
        vm.prank(courier);
        vault.claim();
        assertEq(courier.balance, before + 0.98 ether, "courier must be paid");

        // The bad receiver's own claim reverts, and only its own.
        vm.expectRevert(
            abi.encodeWithSelector(SettlementVault.ClaimTransferFailed.selector, address(badTreasury), 0.02 ether)
        );
        vault.claimFor(address(badTreasury));

        // Its balance is intact and the vault stays solvent.
        assertEq(vault.claimableOf(address(badTreasury)), 0.02 ether, "failed claim must not burn the balance");
        assertGe(address(vault).balance, vault.totalLiabilities(), "vault must stay solvent");
    }

    /// @dev A second delivery settles normally while the first has a stuck receiver.
    function test_StuckReceiverDoesNotBlockOtherDeliveries() public {
        RevertingReceiver bad = new RevertingReceiver();

        _lock(LOCK_A, customer, 1 ether);
        vm.prank(controller);
        vault.releaseLock(LOCK_A, _payouts(address(bad), 1 ether));

        _lock(LOCK_B, customer, 2 ether);
        vm.prank(controller);
        vault.releaseLock(LOCK_B, _payouts(courier, 2 ether));

        uint256 before = courier.balance;
        vm.prank(courier);
        vault.claim();
        assertEq(courier.balance, before + 2 ether, "second delivery settles independently");
    }

    function test_GasBurningReceiverCannotBlockSettlement() public {
        GasBurningReceiver burner = new GasBurningReceiver();
        _lock(LOCK_A, customer, 1 ether);

        vm.prank(controller);
        vault.releaseLock(LOCK_A, _payouts(address(burner), 1 ether));
        assertEq(vault.claimableOf(address(burner)), 1 ether, "crediting must not depend on the receiver");
    }

    // ---------------------------------------------------------- reentrancy

    function test_ReentrantClaimIsBlocked() public {
        ReentrantClaimer attacker = new ReentrantClaimer(vault);

        _lock(LOCK_A, customer, 1 ether);
        vm.prank(controller);
        vault.releaseLock(LOCK_A, _payouts(address(attacker), 1 ether));

        attacker.pull();

        assertTrue(attacker.attempted(), "re-entry path must have been taken");
        assertTrue(attacker.reentryReverted(), "re-entry must be rejected");
        assertEq(vault.claimableOf(address(attacker)), 0);
        assertEq(address(attacker).balance, 1 ether, "attacker gets exactly its own balance, once");
        assertGe(address(vault).balance, vault.totalLiabilities());
    }

    // --------------------------------------------------------------- pause

    /// @dev §45: taking new custody stops, but users can always exit.
    function test_Pause_BlocksLockButAllowsClaim() public {
        _lock(LOCK_A, customer, 1 ether);
        vm.prank(controller);
        vault.releaseLock(LOCK_A, _payouts(courier, 1 ether));

        vm.prank(emergency);
        manager.pause();

        vm.expectRevert(ProtocolAccessManager.EnforcedPause.selector);
        vm.prank(controller);
        vault.lock{value: 1 ether}(LOCK_B, customer);

        // Exit still works.
        uint256 before = courier.balance;
        vm.prank(courier);
        vault.claim();
        assertEq(courier.balance, before + 1 ether, "users must be able to exit while paused");
    }

    /// @dev Releasing while paused only moves internal balances toward users.
    function test_Pause_AllowsReleaseAndRefund() public {
        _lock(LOCK_A, customer, 1 ether);
        vm.prank(emergency);
        manager.pause();

        vm.prank(controller);
        vault.refundLock(LOCK_A);
        assertEq(vault.claimableOf(customer), 1 ether);
    }

    // ---------------------------------------------------------------- fuzz

    function testFuzz_LockReleaseClaimConservesValue(uint96 amount, uint96 courierShare) public {
        amount = uint96(bound(amount, 1, 1_000 ether));
        courierShare = uint96(bound(courierShare, 1, amount));
        uint256 treasuryShare = uint256(amount) - courierShare;

        vm.deal(controller, amount);
        _lock(LOCK_A, customer, amount);

        ISettlementVault.Payout[] memory p;
        if (treasuryShare == 0) {
            p = _payouts(courier, courierShare);
        } else {
            p = new ISettlementVault.Payout[](2);
            p[0] = ISettlementVault.Payout({to: courier, amount: courierShare});
            p[1] = ISettlementVault.Payout({to: treasury, amount: treasuryShare});
        }

        vm.prank(controller);
        vault.releaseLock(LOCK_A, p);

        assertEq(
            vault.claimableOf(courier) + vault.claimableOf(treasury), amount, "credits must equal the locked amount"
        );
        assertGe(address(vault).balance, vault.totalLiabilities(), "vault must stay solvent");

        vm.prank(courier);
        vault.claim();
        if (treasuryShare > 0) {
            vault.claimFor(treasury);
        }

        assertEq(vault.totalClaimable(), 0);
        assertGe(address(vault).balance, vault.totalLiabilities());
    }

    function testFuzz_OnlyControllerCanLock(address caller) public {
        vm.assume(caller != controller);
        vm.deal(caller, 1 ether);
        vm.expectRevert();
        vm.prank(caller);
        vault.lock{value: 1 ether}(LOCK_A, customer);
        assertEq(vault.totalLocked(), 0);
    }

    // -------------------------------------------------------------- surplus

    /// @dev Force-sent value raises the balance above liabilities and must not
    ///      corrupt accounting or become claimable by anyone.
    function test_ForceSentValueBecomesSurplusOnly() public {
        _lock(LOCK_A, customer, 1 ether);
        vm.deal(address(vault), address(vault).balance + 5 ether);

        assertEq(vault.surplus(), 5 ether);
        assertEq(vault.totalLiabilities(), 1 ether);

        vm.prank(controller);
        vault.refundLock(LOCK_A);

        vm.prank(customer);
        vault.claim();
        assertEq(customer.balance, 1 ether, "only the recorded amount is claimable");
        assertEq(vault.surplus(), 5 ether, "surplus stays unclaimable");
    }
}
