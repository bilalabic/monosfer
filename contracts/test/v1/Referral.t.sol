// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProtocolAccessManager} from "../../src/v1/access/ProtocolAccessManager.sol";
import {Referral} from "../../src/v1/rewards/Referral.sol";

/// @dev A referrer that cannot receive MON, to show they hold up nobody else.
contract RejectingReferrer {
    Referral internal immutable ref;

    constructor(Referral ref_) {
        ref = ref_;
    }

    function register(address referrer) external {
        ref.register(referrer);
    }

    function tryClaim() external returns (bool ok) {
        try ref.claim() {
            ok = true;
        } catch {
            ok = false;
        }
    }

    receive() external payable {
        revert("no");
    }
}

/**
 * @notice Referral rules (sec. 25).
 * @dev Two properties carry the weight: a referral pays for *doing* something
 *      rather than for connecting a wallet, and no registration can close a loop.
 */
contract ReferralTest is Test {
    ProtocolAccessManager internal manager;
    Referral internal ref;

    address internal admin = address(0xA11CE);
    address internal treasurer = address(0x7EA51);
    address internal reporter = address(0x9E7);
    address internal stranger = address(0xBAD);

    address internal alice = address(0xA11);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCA401);

    uint128 internal constant REWARD = 1 ether;

    function setUp() public {
        manager = new ProtocolAccessManager(3 days, admin);
        ref = new Referral(manager);

        bytes32 treas = manager.TREASURER_ROLE();
        bytes32 rep = manager.REPUTATION_REPORTER_ROLE();
        vm.startPrank(admin);
        manager.grantRole(treas, treasurer);
        manager.grantRole(rep, reporter);
        vm.stopPrank();

        vm.prank(treasurer);
        ref.setRewardAmount(REWARD);

        vm.deal(treasurer, 100 ether);
        vm.prank(treasurer);
        ref.fund{value: 50 ether}();
    }

    // ------------------------------------------------------- registration

    function test_RegisterRecordsReferrerAndDepth() public {
        vm.prank(bob);
        ref.register(alice);

        assertEq(ref.referrerOf(bob), alice);
        assertEq(ref.depthOf(bob), 1);
        assertEq(ref.depthOf(alice), 0, "a root stays at zero");
    }

    function test_SelfReferralRejected() public {
        vm.prank(alice);
        vm.expectRevert(Referral.SelfReferral.selector);
        ref.register(alice);
    }

    function test_OneReferrerPerWallet() public {
        vm.prank(bob);
        ref.register(alice);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Referral.AlreadyRegistered.selector, bob));
        ref.register(carol);

        assertEq(ref.referrerOf(bob), alice, "the first one stands");
    }

    // ------------------------------------------------------ cycle rejection

    function test_DirectCycleRejected() public {
        vm.prank(bob);
        ref.register(alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Referral.CircularReferral.selector, alice, bob));
        ref.register(bob);
    }

    function test_IndirectCycleRejected() public {
        vm.prank(bob);
        ref.register(alice);
        vm.prank(carol);
        ref.register(bob);

        // alice -> carol would close alice -> carol -> bob -> alice.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Referral.CircularReferral.selector, alice, carol));
        ref.register(carol);
    }

    function test_ChainDepthIsCapped() public {
        address previous = address(uint160(1_000));
        for (uint160 i = 1; i <= ref.MAX_DEPTH(); i++) {
            address next = address(uint160(1_000) + i);
            vm.prank(next);
            ref.register(previous);
            previous = next;
        }
        assertEq(ref.depthOf(previous), ref.MAX_DEPTH());

        address tooFar = address(uint160(2_000));
        vm.prank(tooFar);
        vm.expectRevert(abi.encodeWithSelector(Referral.ChainTooDeep.selector, ref.MAX_DEPTH()));
        ref.register(previous);
    }

    /// @dev No sequence of registrations produces a wallet that refers itself.
    function testFuzz_NoWalletEverBecomesItsOwnAncestor(uint8 seed) public {
        uint256 n = bound(seed, 2, 12);
        address[] memory wallets = new address[](n);
        for (uint256 i = 0; i < n; i++) {
            wallets[i] = address(uint160(5_000 + i));
        }
        for (uint256 i = 1; i < n; i++) {
            vm.prank(wallets[i]);
            try ref.register(wallets[(uint256(seed) + i) % n]) {} catch {}
        }
        for (uint256 i = 0; i < n; i++) {
            address cursor = ref.referrerOf(wallets[i]);
            for (uint256 hop = 0; hop < n + 2 && cursor != address(0); hop++) {
                assertTrue(cursor != wallets[i], "a wallet became its own ancestor");
                cursor = ref.referrerOf(cursor);
            }
        }
    }

    // ------------------------------------------------------- qualification

    /// @dev sec. 25: connecting a wallet earns nothing.
    function test_RegistrationAlonePaysNothing() public {
        vm.prank(bob);
        ref.register(alice);
        assertEq(ref.claimable(alice), 0, "no reward until bob does something");
    }

    function test_QualificationPaysTheReferrer() public {
        vm.prank(bob);
        ref.register(alice);

        vm.prank(reporter);
        ref.recordQualification(bob, Referral.Role.Courier);

        assertEq(ref.claimable(alice), REWARD);
        assertEq(ref.totalOwed(), REWARD);
        assertTrue(ref.qualified(bob));
    }

    /// @dev One reward per referred wallet, whichever hat they wear first.
    function test_SecondQualificationRejected() public {
        vm.prank(bob);
        ref.register(alice);

        vm.prank(reporter);
        ref.recordQualification(bob, Referral.Role.Customer);

        vm.prank(reporter);
        vm.expectRevert(abi.encodeWithSelector(Referral.AlreadyQualified.selector, bob));
        ref.recordQualification(bob, Referral.Role.Courier);

        assertEq(ref.claimable(alice), REWARD, "still one reward");
    }

    function test_QualificationWithoutAReferrerIsRecordedNotPaid() public {
        vm.prank(reporter);
        ref.recordQualification(bob, Referral.Role.Juror);

        assertTrue(ref.qualified(bob));
        assertEq(ref.totalOwed(), 0);
    }

    function test_OnlyReporterMayRecordQualification() public {
        vm.prank(stranger);
        vm.expectRevert();
        ref.recordQualification(bob, Referral.Role.Courier);
    }

    // ------------------------------- the property sec. 25 names explicitly

    /**
     * @dev "Reward failure must never block delivery settlement." The reporter is
     *      a settlement contract, so `recordQualification` must succeed even with
     *      an empty purse. The shortfall is emitted rather than thrown.
     */
    function test_EmptyBudgetDoesNotRevertTheReporter() public {
        Referral poor = new Referral(manager);
        vm.prank(treasurer);
        poor.setRewardAmount(REWARD);

        vm.prank(bob);
        poor.register(alice);

        vm.prank(reporter);
        poor.recordQualification(bob, Referral.Role.Courier);

        assertTrue(poor.qualified(bob), "the qualification is still on the record");
        assertEq(poor.claimable(alice), 0, "but nothing was promised that is not there");
        assertEq(poor.totalOwed(), 0);
    }

    function test_UnconfiguredRewardDoesNotRevertTheReporter() public {
        Referral fresh = new Referral(manager);
        vm.deal(treasurer, 10 ether);
        vm.prank(treasurer);
        fresh.fund{value: 5 ether}();

        vm.prank(bob);
        fresh.register(alice);
        vm.prank(reporter);
        fresh.recordQualification(bob, Referral.Role.Courier);

        assertTrue(fresh.qualified(bob));
        assertEq(fresh.totalOwed(), 0);
    }

    // --------------------------------------------------------------- money

    function test_ReferrerClaimsWhatTheyEarned() public {
        vm.prank(bob);
        ref.register(alice);
        vm.prank(reporter);
        ref.recordQualification(bob, Referral.Role.Courier);

        vm.prank(alice);
        ref.claim();

        assertEq(alice.balance, REWARD);
        assertEq(ref.claimable(alice), 0);
        assertEq(ref.totalOwed(), 0);
    }

    function test_ClaimingNothingRejected() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Referral.NothingToClaim.selector, alice));
        ref.claim();
    }

    /// @dev A referrer who cannot receive MON keeps their balance and blocks nobody.
    function test_RejectingReferrerHoldsUpNobody() public {
        RejectingReferrer rejecting = new RejectingReferrer(ref);

        vm.prank(bob);
        ref.register(address(rejecting));
        vm.prank(carol);
        ref.register(alice);

        vm.startPrank(reporter);
        ref.recordQualification(bob, Referral.Role.Courier);
        ref.recordQualification(carol, Referral.Role.Customer);
        vm.stopPrank();

        assertFalse(rejecting.tryClaim(), "their own withdrawal fails");
        assertEq(ref.claimable(address(rejecting)), REWARD, "and the balance is still theirs");

        vm.prank(alice);
        ref.claim();
        assertEq(alice.balance, REWARD, "everyone else settles normally");
    }

    function test_SurplusIsNotOwedToAnyone() public {
        assertEq(ref.totalOwed(), 0);
        assertEq(ref.surplus(), 50 ether);

        vm.prank(bob);
        ref.register(alice);
        vm.prank(reporter);
        ref.recordQualification(bob, Referral.Role.Courier);

        assertEq(ref.surplus(), 50 ether - REWARD);
    }

    function test_OnlyTreasurerSetsTheRewardAmount() public {
        vm.prank(stranger);
        vm.expectRevert();
        ref.setRewardAmount(5 ether);
    }
}
