// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {ProtocolAccessManager} from "../../src/v1/access/ProtocolAccessManager.sol";
import {ProtocolConfig} from "../../src/v1/config/ProtocolConfig.sol";
import {CourierRegistry} from "../../src/v1/registry/CourierRegistry.sol";
import {ReputationRegistry} from "../../src/v1/reputation/ReputationRegistry.sol";
import {BadgeSBT} from "../../src/v1/badge/BadgeSBT.sol";
import {RewardDistributor} from "../../src/v1/rewards/RewardDistributor.sol";
import {Referral} from "../../src/v1/rewards/Referral.sol";

/**
 * @dev Temporary. Exercises the authorised P3.2 and P3.3 paths on chain. The
 *      rejection cases are driven from the shell, because forge will not
 *      broadcast a batch that contains a reverting call.
 */
contract VerifyP3Script is Script {
    ProtocolAccessManager mgr;
    ProtocolConfig cfg;
    CourierRegistry reg;
    ReputationRegistry rep;
    BadgeSBT badge;
    RewardDistributor rewards;
    Referral referral;

    uint256 pass;
    uint256 fail;

    function check(bool cond, string memory what) internal {
        if (cond) {
            pass++;
            console2.log("  [OK]  ", what);
        } else {
            fail++;
            console2.log("  [FAIL]", what);
        }
    }

    function run() external {
        mgr = ProtocolAccessManager(vm.envAddress("MGR"));
        cfg = ProtocolConfig(vm.envAddress("CFG"));
        reg = CourierRegistry(payable(vm.envAddress("REG")));
        rep = ReputationRegistry(vm.envAddress("REP"));
        badge = BadgeSBT(vm.envAddress("BADGE"));
        rewards = RewardDistributor(payable(vm.envAddress("REWARDS")));
        referral = Referral(payable(vm.envAddress("REFERRAL")));

        uint256 adminKey = vm.envUint("DA_KEY");
        uint256 treasKey = vm.envUint("TREAS_KEY");
        uint256 courKey = vm.envUint("COUR_KEY");
        uint256 custKey = vm.envUint("CUST_KEY");

        address cour = vm.addr(courKey);
        address cust = vm.addr(custKey);
        address treasurer = vm.addr(treasKey);

        vm.startBroadcast(adminKey);
        mgr.grantRole(mgr.TREASURER_ROLE(), treasurer);
        mgr.grantRole(mgr.BADGE_AWARDER_ROLE(), treasurer);
        vm.stopBroadcast();

        _badges(cour);
        _rewards(treasKey, cust);
        _referral(treasKey, custKey, cour);

        console2.log("");
        console2.log("  pass", pass);
        console2.log("  fail", fail);
        require(fail == 0, "on-chain P3 verification failed");
    }

    function _badges(address cour) internal {
        // The courier completed a delivery during the P3.1 run, so the first
        // milestone is genuinely earned rather than arranged for this script.
        check(badge.isEarned(cour, BadgeSBT.BadgeType.FirstDelivery), "first-delivery badge is earned");
        check(!badge.isEarned(cour, BadgeSBT.BadgeType.TenDeliveries), "ten-delivery badge is not");

        vm.startBroadcast();
        badge.claim(cour, BadgeSBT.BadgeType.FirstDelivery);
        vm.stopBroadcast();

        check(badge.balanceOf(cour) == 1, "badge minted to the courier");
        check(badge.locked(0), "and reports itself locked (ERC-5192)");
        check(badge.ownerOf(0) == cour, "held by the courier, not the claimant");
    }

    function _rewards(uint256 treasKey, address cust) internal {
        vm.startBroadcast(treasKey);
        rewards.fundEpoch{value: 0.4 ether}(1);
        vm.stopBroadcast();

        check(rewards.remainingBudget(1) == 0.4 ether, "epoch funded");

        // A two-leaf tree; the customer's proof is the other leaf.
        bytes32 leafA = keccak256(bytes.concat(keccak256(abi.encode(cust, uint256(0.1 ether)))));
        bytes32 leafB = keccak256(bytes.concat(keccak256(abi.encode(address(0xBEEF), uint256(0.2 ether)))));
        bytes32 root = leafA <= leafB ? keccak256(bytes.concat(leafA, leafB)) : keccak256(bytes.concat(leafB, leafA));

        vm.startBroadcast(treasKey);
        rewards.publishRoot(1, root);
        vm.stopBroadcast();

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = leafB;

        uint256 before = cust.balance;
        vm.startBroadcast(treasKey);
        rewards.claim(1, cust, 0.1 ether, proof);
        vm.stopBroadcast();

        check(cust.balance == before + 0.1 ether, "reward paid to the leaf account");
        check(rewards.remainingBudget(1) == 0.3 ether, "and only that much left the budget");
        check(rewards.hasClaimed(1, cust), "claim recorded");
    }

    function _referral(uint256 treasKey, uint256 custKey, address cour) internal {
        vm.startBroadcast(treasKey);
        referral.setRewardAmount(0.05 ether);
        referral.fund{value: 0.2 ether}();
        vm.stopBroadcast();

        vm.startBroadcast(custKey);
        referral.register(cour);
        vm.stopBroadcast();

        address cust = vm.addr(custKey);
        check(referral.referrerOf(cust) == cour, "referrer recorded");
        check(referral.depthOf(cust) == 1, "depth is one below the root");
        check(referral.claimable(cour) == 0, "registration alone pays nothing (sec. 25)");
    }
}
