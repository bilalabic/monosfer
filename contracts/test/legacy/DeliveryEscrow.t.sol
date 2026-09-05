// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MCRYToken} from "../../src/MCRYToken.sol";
import {ReputationBadge} from "../../src/ReputationBadge.sol";
import {Leaderboard} from "../../src/Leaderboard.sol";
import {RewardDistributor} from "../../src/RewardDistributor.sol";
import {DeliveryEscrow} from "../../src/DeliveryEscrow.sol";

contract DeliveryEscrowTest is Test {
    MCRYToken internal token;
    ReputationBadge internal badge;
    Leaderboard internal leaderboard;
    RewardDistributor internal distributor;
    DeliveryEscrow internal escrow;

    address internal owner = address(this);
    address internal treasury = address(0xA11);
    address internal rewardPool = address(0xB22);
    address internal customer = address(0x101);
    address internal courier1 = address(0x202);
    address internal courier2 = address(0x303);

    function setUp() public {
        token = new MCRYToken(100_000_000 ether, owner);
        badge = new ReputationBadge(owner);
        leaderboard = new Leaderboard(owner, address(badge));
        distributor = new RewardDistributor(owner, address(token));
        escrow = new DeliveryEscrow(address(token), address(leaderboard), treasury, rewardPool);

        badge.setMinter(address(leaderboard));
        leaderboard.setEscrowContract(address(escrow));

        token.transfer(customer, 1_000 ether);
        token.transfer(courier1, 1_000 ether);
        token.transfer(courier2, 1_000 ether);
    }

    function test_FullTokenFlow_Works() public {
        vm.startPrank(courier1);
        token.approve(address(escrow), type(uint256).max);
        escrow.depositStake(10 ether);
        vm.stopPrank();

        vm.startPrank(courier2);
        token.approve(address(escrow), type(uint256).max);
        escrow.depositStake(10 ether);
        vm.stopPrank();

        vm.startPrank(customer);
        token.approve(address(escrow), type(uint256).max);
        uint256 requestId = escrow.createDeliveryRequest(
            keccak256("pickup"),
            keccak256("delivery"),
            DeliveryEscrow.Urgency.Express,
            50 ether
        );
        vm.stopPrank();

        vm.prank(courier1);
        escrow.submitBid(requestId, 40 ether, 25);

        vm.prank(courier2);
        escrow.submitBid(requestId, 35 ether, 22);

        vm.prank(customer);
        escrow.acceptBid(requestId, courier2);

        vm.prank(courier2);
        escrow.confirmPickup(requestId);

        vm.warp(block.timestamp + 40 minutes);

        uint256 courierBefore = token.balanceOf(courier2);
        uint256 treasuryBefore = token.balanceOf(treasury);
        uint256 rewardBefore = token.balanceOf(rewardPool);

        vm.prank(customer);
        escrow.confirmDelivery(requestId);

        uint256 fee = (35 ether * 100) / 10000;
        assertEq(token.balanceOf(courier2), courierBefore + (35 ether - fee));
        assertEq(token.balanceOf(treasury), treasuryBefore + fee / 2);
        assertEq(token.balanceOf(rewardPool), rewardBefore + (fee - fee / 2));

        vm.prank(customer);
        escrow.submitRating(requestId, 5);

        (uint32 deliveries,,,,,) = leaderboard.courierStats(courier2);
        assertEq(deliveries, 1);
    }
}
