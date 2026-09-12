// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {ProtocolAccessManager} from "../../src/v1/access/ProtocolAccessManager.sol";
import {ProtocolConfig} from "../../src/v1/config/ProtocolConfig.sol";
import {BaselineParams} from "../../src/v1/config/BaselineParams.sol";
import {ISettlementVault} from "../../src/v1/interfaces/ISettlementVault.sol";
import {CourierRegistry} from "../../src/v1/registry/CourierRegistry.sol";
import {ReputationRegistry} from "../../src/v1/reputation/ReputationRegistry.sol";
import {Referral} from "../../src/v1/rewards/Referral.sol";
import {DeliveryHub} from "../../src/v1/hub/DeliveryHub.sol";
import {JurorPool} from "../../src/v1/dispute/JurorPool.sol";
import {DisputeCourt} from "../../src/v1/dispute/DisputeCourt.sol";
import {FallbackCommittee} from "../../src/v1/dispute/FallbackCommittee.sol";
import {IRandomnessAdapter} from "../../src/v1/randomness/IRandomnessAdapter.sol";

/**
 * @title DeployCompressed
 * @notice A deployment whose lifecycle windows sit at their floor, so sec. 46's
 *         jury flow can be run against a real chain.
 * @dev **This is not a deployment. Never point users at it.**
 *
 *      sec. 28's path takes at least twenty-two days at baseline parameters:
 *      three days of evidence, a day to commit, a day to reveal, two days to
 *      appeal, three times over. A live chain has no way to move its clock, so
 *      the choice is between never exercising the jury on chain and exercising
 *      it with the same code and shorter windows.
 *
 *      This takes the second. Every rule, every signature, every payout and the
 *      real randomness provider are unchanged; only the durations differ, and
 *      they are the one thing `ProtocolConfig` already treats as governable.
 *      What this cannot tell you is whether a three-day window is the right
 *      length — that is a product question, not a code one.
 *
 *      Two guards, because a script that stands up a crippled protocol has to be
 *      hard to run by accident: it refuses any chain that is not the testnet it
 *      was asked for, and it requires the caller to say in an environment
 *      variable that they know what this is.
 *
 *      Contracts that take only the access manager are reused from the real
 *      deployment — the vault, reputation, referral, the randomness adapter and
 *      the committee. Only what binds to `ProtocolConfig` is rebuilt.
 */
contract DeployCompressedScript is Script {
    error NotAcknowledged();
    error WrongChain(uint256 expected, uint256 actual);
    error AddressMissing(string what);
    error NotFresh(string what);

    function run() external {
        // A deployment with ten-minute windows is a test rig. Saying so out loud
        // is the price of creating one.
        if (!vm.envOr("I_KNOW_THIS_IS_A_TEST_RIG", false)) revert NotAcknowledged();

        uint256 expected = vm.envOr("EXPECTED_CHAIN_ID", uint256(0));
        if (expected == 0 || block.chainid != expected) revert WrongChain(expected, block.chainid);

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        ProtocolAccessManager manager = ProtocolAccessManager(_req("ACCESS_MANAGER"));
        ISettlementVault vault = ISettlementVault(_req("SETTLEMENT_VAULT"));
        ReputationRegistry reputation = ReputationRegistry(_req("REPUTATION_REGISTRY"));
        Referral referral = Referral(payable(_req("REFERRAL")));
        IRandomnessAdapter randomness = IRandomnessAdapter(_req("RANDOMNESS_ADAPTER"));
        FallbackCommittee committee = FallbackCommittee(_req("FALLBACK_COMMITTEE"));

        ProtocolConfig.Params memory p = BaselineParams.baseline();
        uint32 w = uint32(vm.envOr("WINDOW_SECONDS", uint256(600)));
        p.evidenceWindow = w;
        p.drawWindow = w;
        p.commitWindow = w;
        p.revealWindow = w;
        p.appealWindow = w;
        // Still has to outlast three full rounds, and `ProtocolConfig` checks it.
        p.disputeWindow = 15 * w;

        vm.startBroadcast(deployerKey);

        ProtocolConfig config = new ProtocolConfig(
            manager,
            uint64(vm.envOr("CONFIG_TIMELOCK", uint256(2 days))),
            p,
            _req("TREASURY"),
            _req("RISK_QUOTE_SIGNER"),
            _req("POD_ATTESTATION_SIGNER")
        );
        CourierRegistry registry = new CourierRegistry(manager, config, vault);
        DeliveryHub hub = new DeliveryHub(manager, config, registry, vault, reputation, referral, 1 ether);
        JurorPool pool = new JurorPool(manager, config);
        DisputeCourt court = new DisputeCourt(manager, config, pool, randomness, referral, hub, committee);

        vm.stopBroadcast();

        if (registry.totalStaked() != 0) revert NotFresh("registry stake");
        if (pool.totalStaked() != 0) revert NotFresh("pool stake");
        if (court.nextDisputeId() != 0) revert NotFresh("court disputes");
        if (hub.nextDeliveryId() != 0) revert NotFresh("hub deliveries");

        console2.log("");
        console2.log("=== COMPRESSED TEST RIG -- not a deployment ===");
        console2.log("window seconds:     ", w);
        console2.log("ProtocolConfig:     ", address(config));
        console2.log("CourierRegistry:    ", address(registry));
        console2.log("DeliveryHub:        ", address(hub));
        console2.log("JurorPool:          ", address(pool));
        console2.log("DisputeCourt:       ", address(court));
        console2.log("");
        console2.log("Roles the admin must grant to these new addresses:");
        console2.log("  VAULT_CONTROLLER_ROLE    -> registry and hub");
        console2.log("  REGISTRY_CONTROLLER_ROLE -> hub");
        console2.log("  DISPUTE_COURT_ROLE       -> court");
    }

    function _req(string memory key) internal view returns (address v) {
        v = vm.envOr(key, address(0));
        if (v == address(0)) revert AddressMissing(key);
    }
}
