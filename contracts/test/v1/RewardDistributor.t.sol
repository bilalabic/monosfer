// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProtocolAccessManager} from "../../src/v1/access/ProtocolAccessManager.sol";
import {ProtocolConfig} from "../../src/v1/config/ProtocolConfig.sol";
import {BaselineParams} from "../../src/v1/config/BaselineParams.sol";
import {RewardDistributor} from "../../src/v1/rewards/RewardDistributor.sol";

/// @dev A treasury that refuses MON, to show a reclaim failure harms only itself.
contract RejectingTreasury {
    receive() external payable {
        revert("no");
    }
}

/**
 * @notice Per-epoch MON rewards (sec. 23, invariant sec. 33-12).
 * @dev The load-bearing test here is `test_ProofFromOneEpochCannotDrainAnother`:
 *      a claim is checked against its own epoch's money, so a correct proof
 *      against a wrongly generated tree still cannot reach another week's budget.
 */
contract RewardDistributorTest is Test {
    ProtocolAccessManager internal manager;
    ProtocolConfig internal config;
    RewardDistributor internal dist;

    address internal admin = address(0xA11CE);
    address internal treasurer = address(0x7EA51);
    address internal treasury = address(0x7EA5);
    address internal stranger = address(0xBAD);

    address internal alice = address(0xA11);
    address internal bob = address(0xB0B);

    function setUp() public {
        manager = new ProtocolAccessManager(3 days, admin);
        config = new ProtocolConfig(manager, 2 days, BaselineParams.baseline(), treasury, address(0x1), address(0x2));
        dist = new RewardDistributor(manager, config);

        bytes32 role = manager.TREASURER_ROLE();
        vm.prank(admin);
        manager.grantRole(role, treasurer);

        vm.deal(treasurer, 1_000 ether);
        vm.deal(stranger, 1_000 ether);
    }

    // ------------------------------------------------------------ helpers

    /// @dev The same second-preimage-safe leaf the contract computes.
    function _leaf(address account, uint256 amount) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(account, amount))));
    }

    /// @dev A two-leaf tree: root = H(min, max), and each leaf's proof is the other.
    function _pair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a <= b ? keccak256(bytes.concat(a, b)) : keccak256(bytes.concat(b, a));
    }

    function _publishPair(uint256 epochId, uint256 aliceAmount, uint256 bobAmount) internal returns (bytes32 root) {
        root = _pair(_leaf(alice, aliceAmount), _leaf(bob, bobAmount));
        vm.prank(treasurer);
        dist.publishRoot(epochId, root);
    }

    function _proofFor(address other, uint256 otherAmount) internal pure returns (bytes32[] memory proof) {
        proof = new bytes32[](1);
        proof[0] = _leaf(other, otherAmount);
    }

    // ------------------------------------------------------- funding path

    function test_AnyoneMayFundAnEpoch() public {
        vm.prank(stranger);
        dist.fundEpoch{value: 5 ether}(1);
        assertEq(dist.epochOf(1).funded, 5 ether, "sponsors fund without a role (sec. 23)");
        assertEq(dist.totalOutstanding(), 5 ether);
    }

    function test_FundingZeroRejected() public {
        vm.expectRevert(RewardDistributor.ZeroAmount.selector);
        dist.fundEpoch{value: 0}(1);
    }

    function test_OnlyTreasurerPublishesRoots() public {
        vm.prank(stranger);
        vm.expectRevert();
        dist.publishRoot(1, keccak256("r"));
    }

    // --------------------------------------------------------- claim path

    function test_ValidClaimPays() public {
        vm.prank(treasurer);
        dist.fundEpoch{value: 10 ether}(1);
        _publishPair(1, 3 ether, 4 ether);

        dist.claim(1, alice, 3 ether, _proofFor(bob, 4 ether));

        assertEq(alice.balance, 3 ether);
        assertEq(dist.epochOf(1).claimed, 3 ether);
        assertEq(dist.remainingBudget(1), 7 ether);
        assertTrue(dist.hasClaimed(1, alice));
    }

    /// @dev The leaf names the recipient, so a keeper can pay the gas.
    function test_ClaimPaysTheLeafNotTheCaller() public {
        vm.prank(treasurer);
        dist.fundEpoch{value: 10 ether}(1);
        _publishPair(1, 3 ether, 4 ether);

        vm.prank(stranger);
        dist.claim(1, alice, 3 ether, _proofFor(bob, 4 ether));
        assertEq(alice.balance, 3 ether, "paid the account in the leaf");
    }

    function test_DoubleClaimRejected() public {
        vm.prank(treasurer);
        dist.fundEpoch{value: 10 ether}(1);
        _publishPair(1, 3 ether, 4 ether);
        dist.claim(1, alice, 3 ether, _proofFor(bob, 4 ether));

        vm.expectRevert(abi.encodeWithSelector(RewardDistributor.AlreadyClaimed.selector, uint256(1), alice));
        dist.claim(1, alice, 3 ether, _proofFor(bob, 4 ether));
    }

    function test_WrongAmountFailsTheProof() public {
        vm.prank(treasurer);
        dist.fundEpoch{value: 10 ether}(1);
        _publishPair(1, 3 ether, 4 ether);

        vm.expectRevert(abi.encodeWithSelector(RewardDistributor.InvalidProof.selector, uint256(1), alice));
        dist.claim(1, alice, 5 ether, _proofFor(bob, 4 ether));
    }

    function test_ClaimBeforeRootRejected() public {
        vm.prank(treasurer);
        dist.fundEpoch{value: 10 ether}(1);
        vm.expectRevert(abi.encodeWithSelector(RewardDistributor.RootNotPublished.selector, uint256(1)));
        dist.claim(1, alice, 3 ether, new bytes32[](0));
    }

    /// @dev sec. 23: 90 days.
    function test_ClaimAfterWindowRejected() public {
        vm.prank(treasurer);
        dist.fundEpoch{value: 10 ether}(1);
        _publishPair(1, 3 ether, 4 ether);
        uint64 closesAt = dist.epochOf(1).publishedAt + config.rewardClaimWindow();

        vm.warp(closesAt + 1);
        vm.expectRevert(abi.encodeWithSelector(RewardDistributor.ClaimWindowClosed.selector, uint256(1), closesAt));
        dist.claim(1, alice, 3 ether, _proofFor(bob, 4 ether));
    }

    function test_ClaimOnTheFinalSecondAccepted() public {
        vm.prank(treasurer);
        dist.fundEpoch{value: 10 ether}(1);
        _publishPair(1, 3 ether, 4 ether);

        vm.warp(dist.epochOf(1).publishedAt + config.rewardClaimWindow());
        dist.claim(1, alice, 3 ether, _proofFor(bob, 4 ether));
        assertEq(alice.balance, 3 ether);
    }

    // ------------------------------------------------- invariant sec. 33-12

    /**
     * @dev The failure this contract exists to prevent. Both epochs are funded,
     *      but epoch 2's tree was generated wrongly and promises more than epoch 2
     *      holds. The proof verifies; the budget check is what stops it, and
     *      epoch 1's money is untouched.
     */
    function test_ProofFromOneEpochCannotDrainAnother() public {
        vm.startPrank(treasurer);
        dist.fundEpoch{value: 100 ether}(1);
        dist.fundEpoch{value: 1 ether}(2);
        vm.stopPrank();

        bytes32 root = _pair(_leaf(alice, 50 ether), _leaf(bob, 1 ether));
        vm.prank(treasurer);
        dist.publishRoot(2, root);

        bytes32[] memory proof = _proofFor(bob, 1 ether);
        vm.expectRevert(
            abi.encodeWithSelector(RewardDistributor.EpochBudgetExceeded.selector, uint256(2), 50 ether, 1 ether)
        );
        dist.claim(2, alice, 50 ether, proof);

        assertEq(dist.remainingBudget(1), 100 ether, "epoch 1 untouched");
        assertEq(address(dist).balance, 101 ether);
    }

    function testFuzz_ClaimsNeverExceedTheEpochBudget(uint96 funded, uint96 aliceAmount, uint96 bobAmount) public {
        funded = uint96(bound(funded, 1, 100 ether));
        aliceAmount = uint96(bound(aliceAmount, 1, 200 ether));
        bobAmount = uint96(bound(bobAmount, 1, 200 ether));

        vm.deal(treasurer, 500 ether);
        vm.prank(treasurer);
        dist.fundEpoch{value: funded}(7);
        _publishPair(7, aliceAmount, bobAmount);

        try dist.claim(7, alice, aliceAmount, _proofFor(bob, bobAmount)) {} catch {}
        try dist.claim(7, bob, bobAmount, _proofFor(alice, aliceAmount)) {} catch {}

        assertLe(dist.epochOf(7).claimed, dist.epochOf(7).funded, "sec. 33-12");
        assertGe(address(dist).balance, dist.totalOutstanding(), "and the contract stays solvent");
    }

    // ------------------------------------------------------ root freezing

    function test_RootCorrectableUntilTheFirstClaim() public {
        vm.prank(treasurer);
        dist.fundEpoch{value: 10 ether}(1);

        vm.prank(treasurer);
        dist.publishRoot(1, keccak256("wrong"));
        _publishPair(1, 3 ether, 4 ether);

        dist.claim(1, alice, 3 ether, _proofFor(bob, 4 ether));

        vm.prank(treasurer);
        vm.expectRevert(abi.encodeWithSelector(RewardDistributor.RootAlreadyRelied.selector, uint256(1)));
        dist.publishRoot(1, keccak256("later"));
    }

    // --------------------------------------------------------- reclaiming

    function test_ReclaimReturnsOnlyTheUnclaimedRemainder() public {
        vm.prank(treasurer);
        dist.fundEpoch{value: 10 ether}(1);
        _publishPair(1, 3 ether, 4 ether);
        dist.claim(1, alice, 3 ether, _proofFor(bob, 4 ether));

        vm.warp(block.timestamp + config.rewardClaimWindow() + config.rewardReclaimDelay());
        vm.prank(treasurer);
        dist.reclaim(1);

        assertEq(treasury.balance, 7 ether, "only what nobody claimed");
        assertEq(dist.totalOutstanding(), 0);
        assertEq(address(dist).balance, 0);
    }

    function test_ReclaimBeforeTheDelayRejected() public {
        vm.prank(treasurer);
        dist.fundEpoch{value: 10 ether}(1);
        _publishPair(1, 3 ether, 4 ether);
        uint64 readyAt = dist.epochOf(1).publishedAt + config.rewardClaimWindow() + config.rewardReclaimDelay();

        // The claim window alone is not enough; sec. 23 adds a delay on top.
        vm.warp(dist.epochOf(1).publishedAt + config.rewardClaimWindow() + 1);
        vm.prank(treasurer);
        vm.expectRevert(abi.encodeWithSelector(RewardDistributor.ReclaimTooEarly.selector, uint256(1), readyAt));
        dist.reclaim(1);
    }

    function test_ReclaimTwiceRejected() public {
        vm.prank(treasurer);
        dist.fundEpoch{value: 10 ether}(1);
        _publishPair(1, 3 ether, 4 ether);

        vm.warp(block.timestamp + config.rewardClaimWindow() + config.rewardReclaimDelay());
        vm.prank(treasurer);
        dist.reclaim(1);

        vm.prank(treasurer);
        vm.expectRevert(abi.encodeWithSelector(RewardDistributor.AlreadyReclaimed.selector, uint256(1)));
        dist.reclaim(1);
    }

    function test_OnlyTreasurerReclaims() public {
        vm.prank(treasurer);
        dist.fundEpoch{value: 10 ether}(1);
        _publishPair(1, 3 ether, 4 ether);
        vm.warp(block.timestamp + config.rewardClaimWindow() + config.rewardReclaimDelay());

        vm.prank(stranger);
        vm.expectRevert();
        dist.reclaim(1);
    }

    /// @dev A treasury that cannot receive blocks only its own reclaim.
    function test_RejectingTreasuryBlocksOnlyItself() public {
        RejectingTreasury rejecting = new RejectingTreasury();
        bytes32 role = manager.CONFIG_ADMIN_ROLE();
        vm.prank(admin);
        manager.grantRole(role, treasurer);
        vm.prank(treasurer);
        config.proposeTreasury(address(rejecting));
        vm.warp(block.timestamp + 2 days);
        vm.prank(treasurer);
        config.executeTreasury();

        vm.prank(treasurer);
        dist.fundEpoch{value: 10 ether}(1);
        _publishPair(1, 3 ether, 4 ether);

        // Claims keep working while the treasury cannot take its remainder.
        dist.claim(1, alice, 3 ether, _proofFor(bob, 4 ether));
        assertEq(alice.balance, 3 ether);

        vm.warp(block.timestamp + config.rewardClaimWindow() + config.rewardReclaimDelay());
        vm.prank(treasurer);
        vm.expectRevert();
        dist.reclaim(1);
    }

    // ----------------------------------------------------------- solvency

    function test_ForcedValueBecomesSurplusNotBudget() public {
        vm.prank(treasurer);
        dist.fundEpoch{value: 10 ether}(1);

        vm.deal(address(this), 5 ether);
        (bool ok,) = address(dist).call{value: 5 ether}("");
        assertTrue(ok);

        assertEq(dist.totalOutstanding(), 10 ether, "a transfer names no epoch");
        assertEq(dist.surplus(), 5 ether, "and is claimable by nobody");
        assertEq(dist.remainingBudget(1), 10 ether);
    }
}
