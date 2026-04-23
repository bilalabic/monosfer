// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {MCRYToken} from "../src/MCRYToken.sol";
import {ReputationBadge} from "../src/ReputationBadge.sol";
import {Leaderboard} from "../src/Leaderboard.sol";
import {RewardDistributor} from "../src/RewardDistributor.sol";
import {DeliveryEscrow} from "../src/DeliveryEscrow.sol";

contract DeploySystemScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        MCRYToken token = new MCRYToken(100_000_000 ether, deployer);
        ReputationBadge badge = new ReputationBadge(deployer);
        Leaderboard leaderboard = new Leaderboard(deployer, address(badge));
        RewardDistributor distributor = new RewardDistributor(deployer, address(token));
        DeliveryEscrow escrow = new DeliveryEscrow(address(token), address(leaderboard), deployer, address(distributor));

        badge.setMinter(address(leaderboard));
        leaderboard.setEscrowContract(address(escrow));
        token.transfer(address(distributor), 1_000_000 ether);

        console2.log("MCRYToken:", address(token));
        console2.log("ReputationBadge:", address(badge));
        console2.log("Leaderboard:", address(leaderboard));
        console2.log("RewardDistributor:", address(distributor));
        console2.log("DeliveryEscrow:", address(escrow));

        vm.stopBroadcast();
    }
}
