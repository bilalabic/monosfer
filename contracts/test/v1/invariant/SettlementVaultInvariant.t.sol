// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {ProtocolAccessManager} from "../../../src/v1/access/ProtocolAccessManager.sol";
import {SettlementVault} from "../../../src/v1/vault/SettlementVault.sol";
import {ISettlementVault} from "../../../src/v1/interfaces/ISettlementVault.sol";

/// @notice Always rejects value. Present so the fuzzer routinely credits an
///         account that can never withdraw, which is the legacy failure mode.
contract Rejector {
    receive() external payable {
        revert("no");
    }
}

/**
 * @notice Drives SettlementVault through random custody, settlement and claim
 *         sequences, including unauthorised callers and a receiver that always
 *         reverts.
 * @dev Tracks value in and value out independently of the vault's own counters,
 *      so conservation is checked against externally observed flow rather than
 *      against the numbers the vault reports about itself.
 */
contract VaultHandler is Test {
    ProtocolAccessManager public immutable manager;
    SettlementVault public immutable vault;
    address public immutable controller;
    address public immutable emergency;
    Rejector public immutable rejector;

    address[] public actors;

    uint256 public totalDeposited;
    uint256 public totalWithdrawn;
    uint256 public locksOpened;
    uint256 public locksSettled;
    uint256 public successfulClaims;

    bytes32[] public activeLocks;

    constructor(ProtocolAccessManager manager_, SettlementVault vault_, address controller_, address emergency_) {
        manager = manager_;
        vault = vault_;
        controller = controller_;
        emergency = emergency_;
        rejector = new Rejector();

        actors.push(address(0xA001));
        actors.push(address(0xA002));
        actors.push(address(0xA003));
        actors.push(address(rejector));
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _caller(uint256 seed) internal view returns (address) {
        // Three quarters authorised, one quarter not.
        return seed % 4 == 0 ? address(uint160(uint256(keccak256(abi.encode(seed))))) : controller;
    }

    function lock(uint256 callerSeed, uint256 ownerSeed, uint96 amount) external {
        amount = uint96(bound(amount, 1, 10 ether));
        bytes32 id = keccak256(abi.encode("lock", locksOpened, amount, ownerSeed));
        address caller = _caller(callerSeed);
        vm.deal(caller, amount);

        vm.prank(caller);
        try vault.lock{value: amount}(id, _actor(ownerSeed)) {
            totalDeposited += amount;
            locksOpened++;
            activeLocks.push(id);
        } catch {}
    }

    function topUp(uint256 callerSeed, uint256 lockSeed, uint96 amount) external {
        if (activeLocks.length == 0) return;
        amount = uint96(bound(amount, 1, 5 ether));
        bytes32 id = activeLocks[lockSeed % activeLocks.length];
        address caller = _caller(callerSeed);
        vm.deal(caller, amount);

        vm.prank(caller);
        try vault.topUpLock{value: amount}(id) {
            totalDeposited += amount;
        } catch {}
    }

    function release(uint256 callerSeed, uint256 lockSeed, uint256 aSeed, uint256 bSeed, uint16 splitBps) external {
        if (activeLocks.length == 0) return;
        uint256 idx = lockSeed % activeLocks.length;
        bytes32 id = activeLocks[idx];

        uint256 amount = vault.lockAmount(id);
        if (amount == 0) return;

        uint256 first = (amount * bound(splitBps, 0, 10_000)) / 10_000;
        if (first == 0) first = amount; // avoid a zero-amount payout leg

        ISettlementVault.Payout[] memory payouts;
        if (first == amount) {
            payouts = new ISettlementVault.Payout[](1);
            payouts[0] = ISettlementVault.Payout({to: _actor(aSeed), amount: amount});
        } else {
            payouts = new ISettlementVault.Payout[](2);
            payouts[0] = ISettlementVault.Payout({to: _actor(aSeed), amount: first});
            payouts[1] = ISettlementVault.Payout({to: _actor(bSeed), amount: amount - first});
        }

        vm.prank(_caller(callerSeed));
        try vault.releaseLock(id, payouts) {
            locksSettled++;
            _removeLock(idx);
        } catch {}
    }

    function refund(uint256 callerSeed, uint256 lockSeed) external {
        if (activeLocks.length == 0) return;
        uint256 idx = lockSeed % activeLocks.length;
        bytes32 id = activeLocks[idx];

        vm.prank(_caller(callerSeed));
        try vault.refundLock(id) {
            locksSettled++;
            _removeLock(idx);
        } catch {}
    }

    function claim(uint256 actorSeed) external {
        address who = _actor(actorSeed);
        uint256 owed = vault.claimableOf(who);
        try vault.claimFor(who) {
            totalWithdrawn += owed;
            successfulClaims++;
        } catch {}
    }

    function pauseToggle(uint256 seed, bool doPause) external {
        address caller = seed % 2 == 0 ? emergency : controller;
        vm.prank(caller);
        if (doPause) {
            try manager.pause() {} catch {}
        } else {
            try manager.scheduleUnpause() {} catch {}
        }
    }

    function _removeLock(uint256 idx) internal {
        activeLocks[idx] = activeLocks[activeLocks.length - 1];
        activeLocks.pop();
    }

    function activeLockCount() external view returns (uint256) {
        return activeLocks.length;
    }
}

contract SettlementVaultInvariantTest is StdInvariant, Test {
    ProtocolAccessManager internal manager;
    SettlementVault internal vault;
    VaultHandler internal handler;

    address internal admin = address(0xA11CE);
    address internal configAdmin = address(0xC0FFEE);
    address internal emergency = address(0xE4E4);
    address internal controller = address(0xC07401);

    function setUp() public {
        manager = new ProtocolAccessManager(3 days, admin);
        vm.startPrank(admin);
        manager.grantRole(manager.CONFIG_ADMIN_ROLE(), configAdmin);
        manager.grantRole(manager.EMERGENCY_ROLE(), emergency);
        manager.grantRole(manager.VAULT_CONTROLLER_ROLE(), controller);
        vm.stopPrank();

        vault = new SettlementVault(manager);
        handler = new VaultHandler(manager, vault, controller, emergency);
        targetContract(address(handler));
    }

    /// @dev Invariant sec. 33-1: the vault is solvent. Its balance must always cover
    ///      every liability it has recorded.
    function invariant_VaultIsSolvent() public view {
        assertGe(address(vault).balance, vault.totalLiabilities(), "vault balance below recorded liabilities");
    }

    /**
     * @dev Invariant sec. 33-3: accounting conserves value. Measured against flow
     *      observed outside the vault, so the vault cannot satisfy this by being
     *      internally consistent about wrong numbers.
     */
    function invariant_ValueIsConserved() public view {
        uint256 netIn = handler.totalDeposited() - handler.totalWithdrawn();
        assertEq(netIn, vault.totalLiabilities(), "deposits minus withdrawals must equal liabilities");
        assertEq(vault.totalLiabilities(), vault.totalLocked() + vault.totalClaimable());
    }

    /// @dev The vault must never owe more than it took in.
    function invariant_NeverOwesMoreThanDeposited() public view {
        assertLe(vault.totalLiabilities(), handler.totalDeposited(), "liabilities exceed all value ever deposited");
    }

    /// @dev A settled lock can never hold value again (invariant sec. 33-2, sec. 33-6).
    function invariant_LockedMatchesActiveLocks() public view {
        if (handler.activeLockCount() == 0) {
            assertEq(vault.totalLocked(), 0, "no active locks but totalLocked is non-zero");
        }
    }

    /// @dev Guards against vacuity: the fuzzer must actually reach settlement
    ///      and withdrawal, otherwise the invariants above prove nothing.
    function test_invariant_HandlerReachesSettlementAndClaim() public {
        handler.lock(1, 0, 5 ether); // authorised caller, actor 0
        assertEq(handler.locksOpened(), 1, "lock must succeed");

        handler.release(1, 0, 0, 0, 10_000);
        assertEq(handler.locksSettled(), 1, "release must succeed");

        handler.claim(0);
        assertEq(handler.successfulClaims(), 1, "claim must succeed");
        assertEq(vault.totalLiabilities(), 0, "everything settled and withdrawn");
    }

    /// @dev A credited account that always reverts on receive must not break
    ///      solvency or block the rest of the system.
    function test_invariant_RejectorCreditIsHeldNotLost() public {
        handler.lock(1, 3, 4 ether); // actor 3 is the Rejector
        handler.release(1, 0, 3, 3, 10_000);

        address rejector = address(handler.rejector());
        assertEq(vault.claimableOf(rejector), 4 ether, "credit must be recorded");

        handler.claim(3); // swallowed failure
        assertEq(vault.claimableOf(rejector), 4 ether, "failed claim must not burn the balance");
        assertGe(address(vault).balance, vault.totalLiabilities(), "still solvent");
    }
}
