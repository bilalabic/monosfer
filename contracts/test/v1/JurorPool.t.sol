// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProtocolAccessManager} from "../../src/v1/access/ProtocolAccessManager.sol";
import {ProtocolConfig} from "../../src/v1/config/ProtocolConfig.sol";
import {BaselineParams} from "../../src/v1/config/BaselineParams.sol";
import {JurorPool} from "../../src/v1/dispute/JurorPool.sol";

/**
 * @notice Juror standing, locks and the frozen draw set (sec. 4.6, sec. 27).
 * @dev The two claims worth proving here are invariant sec. 33-18 — a draw that
 *      has been requested cannot be steered by anyone joining or leaving — and
 *      sec. 27's equal weight, which is really a claim about what the contract
 *      does *not* record.
 */
contract JurorPoolTest is Test {
    ProtocolAccessManager internal manager;
    ProtocolConfig internal config;
    JurorPool internal pool;

    address internal admin = address(0xA11CE);
    address internal court = address(0xC0C0);
    address internal treasury = address(0x7EA5);
    address internal configAdmin = address(0xC0F1);

    address internal alice = address(0xA11);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCA401);

    uint256 internal MIN;
    uint256 internal LOCK;
    uint256 internal SLASH;

    function setUp() public {
        manager = new ProtocolAccessManager(3 days, admin);
        config = new ProtocolConfig(manager, 2 days, BaselineParams.baseline(), treasury, address(0x1), address(0x2));
        pool = new JurorPool(manager, config);

        bytes32 role = manager.DISPUTE_COURT_ROLE();
        bytes32 configRole = manager.CONFIG_ADMIN_ROLE();
        vm.startPrank(admin);
        manager.grantRole(role, court);
        manager.grantRole(configRole, configAdmin);
        vm.stopPrank();

        MIN = config.minJurorStake();
        LOCK = config.jurorLockPerCase();
        SLASH = config.nonRevealSlash();

        for (uint160 i = 1; i <= 10; i++) {
            vm.deal(address(i + 0xA00), 1_000 ether);
        }
        vm.deal(alice, 1_000 ether);
        vm.deal(bob, 1_000 ether);
        vm.deal(carol, 1_000 ether);
    }

    // ------------------------------------------------------------ helpers

    function _join(address who, uint256 amount) internal {
        vm.startPrank(who);
        pool.stake{value: amount}();
        pool.activate();
        vm.stopPrank();
    }

    // ------------------------------------------------------- sec. 27 basics

    function test_StakingAloneDoesNotStandYouForSelection() public {
        vm.prank(alice);
        pool.stake{value: MIN}();

        assertEq(pool.eligibleCount(), 0, "staking is not volunteering");
        assertFalse(pool.isEligible(alice));

        vm.prank(alice);
        pool.activate();
        assertEq(pool.eligibleCount(), 1);
        assertTrue(pool.isEligible(alice));
    }

    function test_BelowMinimumCannotActivate() public {
        vm.startPrank(alice);
        pool.stake{value: MIN - 1}();
        vm.expectRevert(abi.encodeWithSelector(JurorPool.BelowMinimumStake.selector, MIN - 1, MIN));
        pool.activate();
        vm.stopPrank();
    }

    /**
     * @dev sec. 27: stake above the minimum grants no extra weight. Proven by
     *      what the pool records — a juror appears in the candidate list exactly
     *      once regardless of size, and nothing stores a weight at all.
     */
    function test_LargeStakeIsOneCandidateLikeAnyOther() public {
        _join(alice, MIN);
        _join(bob, MIN * 100);

        assertEq(pool.eligibleCount(), 2, "two candidates, not a hundred and one");
        assertEq(pool.eligibleAt(0), alice);
        assertEq(pool.eligibleAt(1), bob);
        assertEq(pool.jurorOf(bob).stake, MIN * 100, "the stake is recorded, just not as weight");
    }

    function test_DeactivateRemovesFromThePool() public {
        _join(alice, MIN);
        _join(bob, MIN);
        _join(carol, MIN);

        vm.prank(bob);
        pool.deactivate();

        assertEq(pool.eligibleCount(), 2);
        assertFalse(pool.isEligible(bob));
        assertTrue(pool.isEligible(alice));
        assertTrue(pool.isEligible(carol));
    }

    // ------------------------------------------------------------ withdrawal

    function test_UnlockedStakeIsWithdrawable() public {
        _join(alice, MIN * 2);
        uint256 before = alice.balance;

        vm.prank(alice);
        pool.withdraw(MIN);

        assertEq(alice.balance, before + MIN);
        assertEq(pool.jurorOf(alice).stake, MIN);
        assertTrue(pool.isEligible(alice), "still above the minimum");
    }

    function test_LockedStakeCannotBeWithdrawn() public {
        _join(alice, MIN);
        vm.prank(court);
        pool.seat(1, alice);

        uint256 free = MIN - LOCK;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(JurorPool.StakeLocked.selector, free + 1, free));
        pool.withdraw(free + 1);

        vm.prank(alice);
        pool.withdraw(free);
        assertEq(pool.jurorOf(alice).stake, LOCK, "the case's lock stays behind");
    }

    /// @dev Dropping below the minimum takes you out rather than leaving a name
    ///      in the list that a draw could pick and then fail to seat.
    function test_WithdrawingBelowTheMinimumLeavesThePool() public {
        _join(alice, MIN * 2);
        vm.prank(alice);
        pool.withdraw(MIN + 1);

        assertFalse(pool.isEligible(alice));
        assertEq(pool.eligibleCount(), 0);
    }

    // --------------------------------------------- invariant sec. 33-18

    /**
     * @dev The draw set is frozen when randomness is requested. Everything that
     *      happens to the pool afterwards is invisible to it — which is what the
     *      invariant asks for.
     */
    function test_SnapshotIgnoresLaterJoinsAndExits() public {
        _join(alice, MIN);
        _join(bob, MIN);

        vm.prank(court);
        pool.takeSnapshot(1);
        assertEq(pool.snapshotSize(1), 2);

        // A latecomer tries to get into the draw.
        _join(carol, MIN);
        // And a candidate tries to get out of it.
        vm.prank(bob);
        pool.deactivate();

        assertEq(pool.snapshotSize(1), 2, "the frozen set did not move");
        assertEq(pool.snapshotAt(1, 0), alice);
        assertEq(pool.snapshotAt(1, 1), bob, "leaving does not remove you from a draw already under way");
        assertEq(pool.eligibleCount(), 2, "while the live pool did change");
    }

    /// @dev Withdrawing below the minimum is the other way out, and is equally ineffective.
    function test_WithdrawingCannotEscapeAPendingDraw() public {
        _join(alice, MIN);
        _join(bob, MIN);

        vm.prank(court);
        pool.takeSnapshot(7);

        vm.prank(bob);
        pool.withdraw(MIN);

        assertFalse(pool.isEligible(bob), "out of the live pool");
        assertEq(pool.snapshotAt(7, 1), bob, "but still in the frozen draw set");
    }

    function test_TwoDrawsHaveIndependentSets() public {
        _join(alice, MIN);
        vm.prank(court);
        pool.takeSnapshot(1);

        _join(bob, MIN);
        vm.prank(court);
        pool.takeSnapshot(2);

        assertEq(pool.snapshotSize(1), 1);
        assertEq(pool.snapshotSize(2), 2);
    }

    function test_SnapshotCannotBeRetaken() public {
        _join(alice, MIN);
        vm.startPrank(court);
        pool.takeSnapshot(1);
        vm.expectRevert(abi.encodeWithSelector(JurorPool.SnapshotExists.selector, uint256(1)));
        pool.takeSnapshot(1);
        vm.stopPrank();
    }

    function test_EmptyPoolCannotBeDrawnFrom() public {
        vm.prank(court);
        vm.expectRevert(abi.encodeWithSelector(JurorPool.SnapshotEmpty.selector, uint256(1)));
        pool.takeSnapshot(1);
    }

    function test_PoolIsCappedSoASnapshotStaysBounded() public {
        uint256 max = pool.MAX_SNAPSHOT();
        for (uint160 i = 0; i < max; i++) {
            address who = address(uint160(0x10000) + i);
            vm.deal(who, MIN);
            vm.startPrank(who);
            pool.stake{value: MIN}();
            pool.activate();
            vm.stopPrank();
        }
        assertEq(pool.eligibleCount(), max);

        vm.deal(alice, MIN);
        vm.startPrank(alice);
        pool.stake{value: MIN}();
        vm.expectRevert(abi.encodeWithSelector(JurorPool.PoolFull.selector, max));
        pool.activate();
        vm.stopPrank();
    }

    // ------------------------------------------------ seating and slashing

    function test_SeatingLocksThePerCaseStake() public {
        _join(alice, MIN);
        vm.prank(court);
        bool seated = pool.seat(1, alice);

        assertTrue(seated);
        assertEq(pool.jurorOf(alice).locked, LOCK);
        assertEq(pool.jurorOf(alice).cases, 1);
    }

    /// @dev A juror who cannot cover the lock is skipped, not forced in.
    function test_SeatingFailsQuietlyWhenStakeIsCommitted() public {
        _join(alice, MIN);
        vm.startPrank(court);
        for (uint256 i = 0; i < MIN / LOCK; i++) {
            assertTrue(pool.seat(i, alice), "fills up to the stake");
        }
        assertFalse(pool.seat(999, alice), "and then declines rather than reverting");
        vm.stopPrank();
    }

    function test_ReleaseReturnsTheLock() public {
        _join(alice, MIN);
        vm.startPrank(court);
        pool.seat(1, alice);
        pool.release(1, alice);
        vm.stopPrank();

        assertEq(pool.jurorOf(alice).locked, 0);
        assertEq(pool.jurorOf(alice).cases, 0);
    }

    /**
     * @dev Invariant sec. 33-14. The only slashing path this contract has is the
     *      non-reveal one, and it takes no argument describing how anyone voted.
     *      A juror in the minority who revealed cannot be reached by it.
     */
    function test_TheOnlySlashingPathIsFailureToReveal() public {
        _join(alice, MIN);
        vm.startPrank(court);
        pool.seat(1, alice);
        pool.slashForNonReveal(1, alice);
        vm.stopPrank();

        assertEq(pool.jurorOf(alice).stake, MIN - SLASH);
        assertEq(pool.jurorOf(alice).locked, 0, "the rest of the lock comes back");
        assertEq(pool.slashedTotal(), SLASH);
    }

    /// @dev A slash that drops a juror under the minimum takes them out too.
    function test_SlashBelowMinimumRemovesFromPool() public {
        _join(alice, MIN);
        vm.startPrank(court);
        pool.seat(1, alice);
        pool.slashForNonReveal(1, alice);
        vm.stopPrank();

        assertFalse(pool.isEligible(alice));
        assertEq(pool.eligibleCount(), 0);
    }

    function test_SlashedStakeLeavesTheOwedTotal() public {
        _join(alice, MIN);
        uint256 owedBefore = pool.totalStaked();

        vm.startPrank(court);
        pool.seat(1, alice);
        pool.slashForNonReveal(1, alice);
        vm.stopPrank();

        assertEq(pool.totalStaked(), owedBefore - SLASH, "no longer owed to the juror");
        assertEq(pool.surplus(), SLASH, "and held as slashed stake");
        assertGe(address(pool).balance, pool.totalStaked(), "still solvent");
    }

    // ------------------------------------------------------ authorisation

    function test_OnlyTheCourtMaySeatReleaseOrSlash() public {
        _join(alice, MIN);

        vm.prank(bob);
        vm.expectRevert();
        pool.seat(1, alice);

        vm.prank(bob);
        vm.expectRevert();
        pool.release(1, alice);

        vm.prank(bob);
        vm.expectRevert();
        pool.slashForNonReveal(1, alice);

        vm.prank(bob);
        vm.expectRevert();
        pool.takeSnapshot(1);
    }

    // ----------------------------------------------------------------- fuzz

    /// @dev Whatever happens to the pool afterwards, a frozen set stays frozen.
    function testFuzz_SnapshotIsImmutable(uint8 joins, uint8 exits) public {
        _join(alice, MIN);
        _join(bob, MIN);
        _join(carol, MIN);

        vm.prank(court);
        uint256 size = pool.takeSnapshot(42);
        address first = pool.snapshotAt(42, 0);

        joins = uint8(bound(joins, 0, 20));
        exits = uint8(bound(exits, 0, 3));
        for (uint160 i = 0; i < joins; i++) {
            address who = address(uint160(0x20000) + i);
            vm.deal(who, MIN);
            vm.startPrank(who);
            pool.stake{value: MIN}();
            pool.activate();
            vm.stopPrank();
        }
        address[3] memory originals = [alice, bob, carol];
        for (uint256 i = 0; i < exits; i++) {
            vm.prank(originals[i]);
            pool.deactivate();
        }

        assertEq(pool.snapshotSize(42), size, "size unchanged");
        assertEq(pool.snapshotAt(42, 0), first, "and so is who is in it");
    }

    /// @dev Solvency holds through any sequence of stakes and withdrawals.
    function testFuzz_PoolStaysSolvent(uint96 a, uint96 b, uint96 w) public {
        a = uint96(bound(a, MIN, 100 ether));
        b = uint96(bound(b, MIN, 100 ether));
        w = uint96(bound(w, 0, 100 ether));

        vm.deal(alice, 200 ether);
        vm.deal(bob, 200 ether);
        _join(alice, a);
        _join(bob, b);

        vm.prank(alice);
        try pool.withdraw(w) {} catch {}

        assertGe(address(pool).balance, pool.totalStaked(), "balance covers what is owed");
    }

    // ------------------------------------- what a seat holds, and for how long

    /// @dev Moves `jurorLockPerCase` to `to`, timelock and all.
    function _setLockPerCase(uint96 to) internal {
        ProtocolConfig.Params memory p = config.params();
        p.jurorLockPerCase = to;
        vm.prank(configAdmin);
        config.proposeParams(p);
        vm.warp(block.timestamp + 2 days);
        vm.prank(configAdmin);
        config.executeParams();
    }

    /**
     * @dev A case outlives the transaction that opened it, and `jurorLockPerCase`
     *      is governable. Releasing whatever the parameter says *now* rather than
     *      what was locked *then* lets a mid-case rise reach into the juror's
     *      other seats: the release is clamped to the total locked, so the excess
     *      comes out of a case that is still running.
     */
    function test_ARaisedLockDoesNotUnlockAnotherCasesCollateral() public {
        _join(alice, MIN * 4);

        vm.startPrank(court);
        pool.seat(1, alice);
        pool.seat(2, alice);
        vm.stopPrank();
        assertEq(pool.jurorOf(alice).locked, uint96(LOCK * 2), "two seats, two locks");

        _setLockPerCase(uint96(LOCK * 2));

        vm.prank(court);
        pool.release(1, alice);

        assertEq(pool.jurorOf(alice).locked, uint96(LOCK), "case 2 still holds exactly its own lock");
        assertEq(pool.jurorOf(alice).cases, 1, "and is still counted as open");
    }

    /**
     * @dev The mirror image: a lowered parameter must not strand the difference.
     *      Nothing in the contract could ever release it — the seat is gone and
     *      the amount is only ever re-read from config.
     */
    function test_ALoweredLockStillFreesTheWholeSeat() public {
        assertLt(SLASH, LOCK, "the baseline must leave room to lower the lock, or this proves nothing");
        _join(alice, MIN * 4);

        vm.prank(court);
        pool.seat(1, alice);

        _setLockPerCase(uint96(SLASH));

        vm.prank(court);
        pool.release(1, alice);

        assertEq(pool.jurorOf(alice).locked, 0, "nothing stayed locked");

        // The consequence, made concrete: the exit that would otherwise be refused.
        uint256 before = alice.balance;
        vm.startPrank(alice);
        pool.deactivate();
        pool.withdraw(uint96(MIN * 4));
        vm.stopPrank();
        assertEq(alice.balance - before, MIN * 4, "the whole stake came back");
    }

    /// @dev One seat per juror per draw, however many times the caller visits them.
    function test_AJurorCannotBeSeatedTwiceOnTheSameDraw() public {
        _join(alice, MIN * 4);

        vm.prank(court);
        bool first = pool.seat(7, alice);
        vm.prank(court);
        bool second = pool.seat(7, alice);

        assertTrue(first, "seated once");
        assertFalse(second, "and refused the second time");
        assertEq(pool.jurorOf(alice).locked, uint96(LOCK), "one seat, one lock");
        assertEq(pool.jurorOf(alice).cases, 1, "and one vote's worth of weight");
    }

    /// @dev Releasing twice must not free a lock that was never taken.
    function test_ReleasingASeatTwiceFreesItOnlyOnce() public {
        _join(alice, MIN * 4);

        vm.startPrank(court);
        pool.seat(1, alice);
        pool.seat(2, alice);
        pool.release(1, alice);
        pool.release(1, alice);
        vm.stopPrank();

        assertEq(pool.jurorOf(alice).locked, uint96(LOCK), "case 2 is untouched");
        assertEq(pool.jurorOf(alice).cases, 1);
    }

    /// @dev A juror who sat in round one can stand again when a dispute is appealed.
    function test_AReleasedJurorCanBeSeatedAgain() public {
        _join(alice, MIN * 4);

        vm.startPrank(court);
        pool.seat(1, alice);
        pool.release(1, alice);
        bool again = pool.seat(1, alice);
        vm.stopPrank();

        assertTrue(again, "a given-up seat is not a permanent bar");
        assertEq(pool.jurorOf(alice).locked, uint96(LOCK));
    }

    /// @dev Slashing gives up the seat as well, and by the same accounting.
    function test_SlashingReleasesExactlyTheSeatedAmount() public {
        _join(alice, MIN * 4);

        vm.startPrank(court);
        pool.seat(1, alice);
        pool.seat(2, alice);
        vm.stopPrank();

        _setLockPerCase(uint96(LOCK * 2));

        vm.prank(court);
        pool.slashForNonReveal(1, alice);

        assertEq(pool.jurorOf(alice).locked, uint96(LOCK), "case 2 keeps its lock");
        (bool held,) = pool.seatOf(1, alice);
        assertFalse(held, "and the slashed seat is gone");
    }
}
