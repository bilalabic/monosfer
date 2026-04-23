// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/Delivera.sol";

contract DeliveraTest is Test {
    Delivera public market;

    address treasury = address(0xA11);
    address rewardPool = address(0xB22);
    address customer = address(0x1);
    address courier1 = address(0x2);
    address courier2 = address(0x3);
    address courier3 = address(0x4);

    bytes32 constant PICKUP = keccak256("Ulus, Ankara");
    bytes32 constant DELIVERY = keccak256("Cankaya, Ankara");

    function setUp() public {
        market = new Delivera(treasury, rewardPool);

        vm.deal(customer, 10 ether);
        vm.deal(courier1, 1 ether);
        vm.deal(courier2, 1 ether);
        vm.deal(courier3, 1 ether);
        vm.deal(treasury, 0);
        vm.deal(rewardPool, 0);

        vm.prank(courier1);
        market.registerCourier{value: 0.01 ether}();
        vm.prank(courier2);
        market.registerCourier{value: 0.01 ether}();
        vm.prank(courier3);
        market.registerCourier{value: 0.01 ether}();
    }

    function test_FullDeliveryFlow() public {
        vm.prank(customer);
        uint256 requestId =
            market.createDeliveryRequest{value: 0.1 ether}(PICKUP, DELIVERY, Delivera.Urgency.Express);
        assertEq(requestId, 0);

        vm.prank(courier1);
        market.submitBid(requestId, 0.08 ether, 25);
        vm.prank(courier2);
        market.submitBid(requestId, 0.05 ether, 30);
        vm.prank(courier3);
        market.submitBid(requestId, 0.07 ether, 22);

        assertEq(market.lockedBidDeposits(requestId, courier1), 0.001 ether);
        assertEq(market.lockedBidDeposits(requestId, courier2), 0.001 ether);
        assertEq(market.lockedBidDeposits(requestId, courier3), 0.001 ether);

        uint256 customerBefore = customer.balance;
        vm.prank(customer);
        market.acceptBid(requestId, courier3);

        assertEq(customer.balance, customerBefore + 0.03 ether);
        assertEq(market.lockedBidDeposits(requestId, courier1), 0);
        assertEq(market.lockedBidDeposits(requestId, courier2), 0);
        assertEq(market.lockedBidDeposits(requestId, courier3), 0.001 ether);

        vm.warp(block.timestamp + 5 minutes);
        vm.prank(courier3);
        market.confirmPickup(requestId);

        vm.warp(block.timestamp + 45 minutes);
        uint256 courierBalanceBefore = courier3.balance;
        uint256 treasuryBefore = treasury.balance;
        uint256 rewardBefore = rewardPool.balance;

        vm.prank(customer);
        market.confirmDelivery(requestId);

        uint256 expectedFee = (0.07 ether * 100) / 10000;
        uint256 expectedNet = 0.07 ether - expectedFee;
        assertEq(courier3.balance, courierBalanceBefore + expectedNet);
        assertEq(treasury.balance, treasuryBefore + (expectedFee / 2));
        assertEq(rewardPool.balance, rewardBefore + (expectedFee - (expectedFee / 2)));
        assertEq(market.lockedBidDeposits(requestId, courier3), 0);
        assertEq(market.courierStake(courier3), 0.01 ether);

        vm.prank(customer);
        market.submitRating(requestId, 5);

        (uint32 totalDeliveries,,,, uint256 score,) = market.courierStats(courier3);
        assertEq(totalDeliveries, 1);
        assertGt(score, 0);
    }

    function test_Leaderboard_ThreeCouriers() public {
        _completeDelivery(customer, courier1, 5, true);
        _completeDelivery(customer, courier1, 5, true);
        _completeDelivery(customer, courier1, 5, true);

        _completeDelivery(customer, courier2, 4, true);
        _completeDelivery(customer, courier2, 4, false);

        _completeDelivery(customer, courier3, 3, true);

        (address[] memory top, uint256[] memory scores) = market.getLeaderboard(3);
        assertEq(top[0], courier1);
        assertGt(scores[0], scores[1]);
        assertGt(scores[1], scores[2]);
    }

    function _completeDelivery(address cust, address cour, uint8 stars, bool onTime) internal {
        vm.deal(cust, 1 ether);
        vm.prank(cust);
        uint256 id = market.createDeliveryRequest{value: 0.05 ether}(PICKUP, DELIVERY, Delivera.Urgency.Express);

        vm.prank(cour);
        market.submitBid(id, 0.04 ether, 30);

        vm.prank(cust);
        market.acceptBid(id, cour);

        vm.prank(cour);
        market.confirmPickup(id);

        vm.warp(block.timestamp + (onTime ? 45 minutes : 2 hours));

        vm.prank(cust);
        market.confirmDelivery(id);

        vm.prank(cust);
        market.submitRating(id, stars);
    }

    function test_CannotBidWithoutRegistration() public {
        address fakeCourier = address(0x99);

        vm.prank(customer);
        uint256 id = market.createDeliveryRequest{value: 0.1 ether}(PICKUP, DELIVERY, Delivera.Urgency.Standard);

        vm.prank(fakeCourier);
        vm.expectRevert("Not registered courier");
        market.submitBid(id, 0.05 ether, 30);
    }

    function test_OnlyCustomerCanAcceptBid() public {
        vm.prank(customer);
        uint256 id = market.createDeliveryRequest{value: 0.1 ether}(PICKUP, DELIVERY, Delivera.Urgency.Standard);

        vm.prank(courier1);
        market.submitBid(id, 0.05 ether, 30);

        vm.prank(courier2);
        vm.expectRevert("Not customer");
        market.acceptBid(id, courier1);
    }
}
