// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/Delivera.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        Delivera market = new Delivera(deployer, deployer);
        console.log("Delivera deployed to:", address(market));
        console.log("Platform treasury:", market.platformTreasury());
        console.log("Reward pool:", market.rewardPool());
        console.log("Min courier stake:", market.MIN_COURIER_STAKE());
        console.log("Bid deposit:", market.BID_DEPOSIT());
        console.log("Platform fee bps:", market.PLATFORM_FEE_BPS());

        vm.stopBroadcast();
    }
}
