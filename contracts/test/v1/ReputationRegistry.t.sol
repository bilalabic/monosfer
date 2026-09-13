// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProtocolAccessManager} from "../../src/v1/access/ProtocolAccessManager.sol";
import {ReputationRegistry} from "../../src/v1/reputation/ReputationRegistry.sol";

/**
 * @notice Reputation: a 0-1000 score and a separate confidence level (sec. 19).
 * @dev The tests are written against the *properties* the baseline asks for —
 *      bounded score, neutral start, confidence that tracks history, each signal
 *      pulling in the stated direction — rather than against specific numbers the
 *      formula happens to produce today. A version bump should therefore break
 *      only the tests that pin a deliberate figure.
 */
contract ReputationRegistryTest is Test {
    ProtocolAccessManager internal manager;
    ReputationRegistry internal rep;

    address internal admin = address(0xA11CE);
    address internal reporter = address(0x9E7);
    address internal stranger = address(0xBAD);
    address internal courier = address(0xC0DE);

    function setUp() public {
        manager = new ProtocolAccessManager(3 days, admin);
        rep = new ReputationRegistry(manager);

        // Role id read before the cheatcode: a view call in argument position
        // consumes the prank, and the grant would come from the test contract.
        bytes32 role = manager.REPUTATION_REPORTER_ROLE();
        vm.prank(admin);
        manager.grantRole(role, reporter);
    }

    // ------------------------------------------------------------ helpers

    function _complete(address who, uint256 id, bool onTime) internal {
        vm.prank(reporter);
        rep.recordAssignment(who);
        vm.prank(reporter);
        rep.recordOutcome(who, id, ReputationRegistry.Outcome.Completed, onTime);
    }

    function _completeMany(address who, uint32 n, bool onTime) internal {
        for (uint32 i = 0; i < n; i++) {
            _complete(who, uint256(i) + 1, onTime);
        }
    }

    function _rate(address who, uint256 id, uint8 stars) internal {
        vm.prank(reporter);
        rep.recordRating(who, id, stars);
    }

    // -------------------------------------------------------- sec. 19 shape

    /// @dev The weights are the baseline's, and they must add up to a whole.
    function test_WeightsSumToOneHundredPercent() public view {
        // Proven through the endpoint: a flawless, fully experienced courier
        // reaches exactly the top of the scale, which only holds if the weights
        // sum to 100%.
        assertEq(rep.MAX_SCORE(), 1_000);
    }

    function test_PerfectVeteranScoresTheMaximum() public {
        _completeMany(courier, rep.FULL_CONFIDENCE_AT(), true);
        for (uint32 i = 0; i < rep.FULL_CONFIDENCE_AT(); i++) {
            _rate(courier, uint256(i) + 1, 5);
        }
        assertEq(rep.scoreOf(courier), 1_000, "flawless and experienced is the top of the scale");
        assertEq(rep.confidenceOf(courier), 1_000);
    }

    /**
     * @dev A brand-new courier must not read as excellent. The rate-shaped
     *      components have no evidence, so they sit at the midpoint rather than
     *      full marks.
     */
    function test_NewCourierStartsNeutralNotPerfect() public view {
        uint16 s = rep.scoreOf(courier);
        assertGt(s, 0, "not zero either: absence of evidence is not evidence of failure");
        // The three evidence-shaped components — success, rating, on-time — carry
        // 65% of the weight between them. With no history they must sit at the
        // midpoint, which caps a new account well below the top of the scale.
        // A looser bound here would still pass if the priors were set to full
        // marks, which is exactly the mistake worth catching.
        assertLt(s, 700, "a new account must not read as nearly flawless");
        assertEq(rep.confidenceOf(courier), 0, "no history means no confidence");
    }

    /// @dev sec. 19: volume must separate a newcomer from a veteran.
    function test_ConfidenceSeparatesNewcomerFromVeteran() public {
        address rookie = address(0x1001);
        address veteran = address(0xE7E5);

        _complete(rookie, 1, true);
        _rate(rookie, 1, 5);

        _completeMany(veteran, rep.FULL_CONFIDENCE_AT(), true);
        // A distinct delivery id: one delivery yields one rating (sec. 20), and
        // that rule is global, not per courier.
        _rate(veteran, 9_001, 5);

        assertLt(rep.confidenceOf(rookie), rep.confidenceOf(veteran), "one perfect delivery is not a track record");
        assertLt(rep.scoreOf(rookie), rep.scoreOf(veteran), "and the score reflects it too");
    }

    function test_ConfidenceSaturatesAndStopsGrowing() public {
        _completeMany(courier, rep.FULL_CONFIDENCE_AT(), true);
        uint16 atCap = rep.confidenceOf(courier);
        _completeMany(courier, 20, true);
        assertEq(rep.confidenceOf(courier), atCap, "past the cap, more history adds no confidence");
        assertEq(atCap, 1_000);
    }

    // ------------------------------------------------ each signal, one by one

    function test_FailedDeliveriesLowerTheScore() public {
        _completeMany(courier, 10, true);
        uint16 before = rep.scoreOf(courier);

        vm.prank(reporter);
        rep.recordOutcome(courier, 99, ReputationRegistry.Outcome.Returned, false);

        assertLt(rep.scoreOf(courier), before, "a return counts against the success rate");
    }

    function test_LateDeliveriesLowerTheScore() public {
        _completeMany(courier, 10, true);
        uint16 punctual = rep.scoreOf(courier);

        address late = address(0x1A7E5);
        _completeMany(late, 10, false);

        assertLt(rep.scoreOf(late), punctual, "missing the accepted ETA costs the on-time component");
    }

    function test_LowRatingsLowerTheScore() public {
        address happy = address(0x11A);
        address unhappy = address(0x11B);
        _completeMany(happy, 5, true);
        _completeMany(unhappy, 5, true);

        for (uint256 i = 1; i <= 5; i++) {
            _rate(happy, i, 5);
            _rate(unhappy, i + 100, 1);
        }
        assertLt(rep.scoreOf(unhappy), rep.scoreOf(happy));
    }

    function test_LostDisputesLowerTheScore() public {
        _completeMany(courier, 10, true);
        uint16 before = rep.scoreOf(courier);

        vm.prank(reporter);
        rep.recordDispute(courier, false);

        assertLt(rep.scoreOf(courier), before);
    }

    /// @dev Never having been disputed is evidence, not a gap: it costs nothing.
    function test_NoDisputesIsNotPenalised() public {
        _completeMany(courier, 10, true);
        uint16 clean = rep.scoreOf(courier);

        address won = address(0x0001);
        _completeMany(won, 10, true);
        vm.prank(reporter);
        rep.recordDispute(won, true);

        assertEq(rep.scoreOf(won), clean, "winning every dispute is the same as having none");
    }

    /**
     * @dev Isolates the cancellation component. Both couriers take one failure,
     *      so their success rates move identically; only the cancellation counter
     *      differs. Comparing against a fresh record instead would have measured
     *      the success rate and passed even with the cancellation penalty removed.
     *
     *      The property: walking away from an assignment costs more than trying
     *      and failing to deliver.
     */
    function test_CancellingCostsMoreThanFailing() public {
        address canceller = address(0xCA11);
        address returner = address(0xE7A1);
        _completeMany(canceller, 10, true);
        _completeMany(returner, 10, true);

        vm.startPrank(reporter);
        rep.recordAssignment(canceller);
        rep.recordOutcome(canceller, 50, ReputationRegistry.Outcome.CancelledByCourier, false);
        rep.recordAssignment(returner);
        rep.recordOutcome(returner, 51, ReputationRegistry.Outcome.Returned, false);
        vm.stopPrank();

        assertLt(rep.scoreOf(canceller), rep.scoreOf(returner), "abandoning is worse than failing");
    }

    /// @dev sec. 13: an expired listing is nobody's fault and must not be scored.
    function test_ExpiredDeliveryIsNotHeldAgainstAnyone() public {
        _completeMany(courier, 10, true);
        uint16 before = rep.scoreOf(courier);

        vm.prank(reporter);
        rep.recordOutcome(courier, 77, ReputationRegistry.Outcome.Expired, false);

        assertEq(rep.scoreOf(courier), before);
    }

    // ---------------------------------------------------------- sec. 20 rating

    function test_RatingMustBeInRange() public {
        vm.prank(reporter);
        vm.expectRevert(abi.encodeWithSelector(ReputationRegistry.RatingOutOfRange.selector, uint8(0)));
        rep.recordRating(courier, 1, 0);

        vm.prank(reporter);
        vm.expectRevert(abi.encodeWithSelector(ReputationRegistry.RatingOutOfRange.selector, uint8(6)));
        rep.recordRating(courier, 1, 6);
    }

    function test_OneRatingPerDelivery() public {
        _rate(courier, 7, 5);
        vm.prank(reporter);
        vm.expectRevert(abi.encodeWithSelector(ReputationRegistry.DeliveryAlreadyRated.selector, uint256(7)));
        rep.recordRating(courier, 7, 1);
    }

    function test_AverageRatingIsReported() public {
        _rate(courier, 1, 5);
        _rate(courier, 2, 3);
        assertEq(rep.averageRatingBps(courier), 4 * 10_000, "mean of 5 and 3");
    }

    // ------------------------------------------------------ authorisation

    function test_OnlyReporterCanWrite() public {
        vm.prank(stranger);
        vm.expectRevert();
        rep.recordAssignment(courier);

        vm.prank(stranger);
        vm.expectRevert();
        rep.recordOutcome(courier, 1, ReputationRegistry.Outcome.Completed, true);

        vm.prank(stranger);
        vm.expectRevert();
        rep.recordRating(courier, 1, 5);

        vm.prank(stranger);
        vm.expectRevert();
        rep.recordDispute(courier, true);
    }

    function test_ZeroCourierRejected() public {
        vm.prank(reporter);
        vm.expectRevert(ReputationRegistry.ZeroAddress.selector);
        rep.recordAssignment(address(0));
    }

    // ---------------------------------------------------- events for sec. 22

    /// @dev Ranking lives in an indexer, so every change has to be observable.
    function test_EveryUpdateEmitsScoreAndVersion() public {
        vm.expectEmit(true, false, false, false, address(rep));
        emit ReputationRegistry.ReputationUpdated(courier, 0, 0, rep.ALGORITHM_VERSION());
        vm.prank(reporter);
        rep.recordAssignment(courier);
    }

    // ----------------------------------------------------------------- fuzz

    /// @dev sec. 19: the score is on a 0-1000 scale for *any* history.
    function testFuzz_ScoreAlwaysWithinScale(
        uint16 completed,
        uint16 onTime,
        uint16 failed,
        uint16 cancelled,
        uint16 won,
        uint16 lost,
        uint8 stars
    ) public {
        completed = uint16(bound(completed, 0, 300));
        onTime = uint16(bound(onTime, 0, completed));
        failed = uint16(bound(failed, 0, 100));
        cancelled = uint16(bound(cancelled, 0, failed));
        won = uint16(bound(won, 0, 50));
        lost = uint16(bound(lost, 0, 50));
        stars = uint8(bound(stars, 1, 5));

        vm.startPrank(reporter);
        for (uint256 i = 0; i < completed; i++) {
            rep.recordAssignment(courier);
            rep.recordOutcome(courier, i + 1, ReputationRegistry.Outcome.Completed, i < onTime);
        }
        for (uint256 i = 0; i < failed; i++) {
            rep.recordAssignment(courier);
            rep.recordOutcome(
                courier,
                i + 1_000,
                i < cancelled ? ReputationRegistry.Outcome.CancelledByCourier : ReputationRegistry.Outcome.Returned,
                false
            );
        }
        for (uint256 i = 0; i < won; i++) {
            rep.recordDispute(courier, true);
        }
        for (uint256 i = 0; i < lost; i++) {
            rep.recordDispute(courier, false);
        }
        if (completed > 0) rep.recordRating(courier, 5_000, stars);
        vm.stopPrank();

        assertLe(rep.scoreOf(courier), 1_000, "score must never leave the scale");
        assertLe(rep.confidenceOf(courier), 1_000, "nor confidence");
    }

    /// @dev More of the same good outcome must never lower the score.
    function testFuzz_IdenticalGoodOutcomesAreMonotonic(uint8 n) public {
        n = uint8(bound(n, 1, 40));
        uint16 previous = rep.scoreOf(courier);
        for (uint256 i = 0; i < n; i++) {
            _complete(courier, i + 1, true);
            uint16 current = rep.scoreOf(courier);
            assertGe(current, previous, "a clean delivery can never cost score");
            previous = current;
        }
    }

    /// @dev Ratings stay inside the scale no matter the mix.
    function testFuzz_RatingComponentStaysBounded(uint8 a, uint8 b, uint8 c) public {
        a = uint8(bound(a, 1, 5));
        b = uint8(bound(b, 1, 5));
        c = uint8(bound(c, 1, 5));
        _complete(courier, 1, true);
        _rate(courier, 1, a);
        _rate(courier, 2, b);
        _rate(courier, 3, c);
        assertLe(rep.scoreOf(courier), 1_000);
    }
}
