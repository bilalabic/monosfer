// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {ProtocolAccessManager} from "../../src/v1/access/ProtocolAccessManager.sol";
import {ProtocolConfig} from "../../src/v1/config/ProtocolConfig.sol";
import {DeliveryHub} from "../../src/v1/hub/DeliveryHub.sol";
import {Referral} from "../../src/v1/rewards/Referral.sol";
import {JurorPool} from "../../src/v1/dispute/JurorPool.sol";
import {DisputeCourt} from "../../src/v1/dispute/DisputeCourt.sol";
import {FallbackCommittee} from "../../src/v1/dispute/FallbackCommittee.sol";
import {PythEntropyAdapter} from "../../src/v1/randomness/PythEntropyAdapter.sol";
import {IEntropyV2} from "../../src/v1/randomness/PythEntropyAdapter.sol";
import {IRandomnessAdapter} from "../../src/v1/randomness/IRandomnessAdapter.sol";

/**
 * @title DeployDispute
 * @notice Deploys the P4 dispute layer against an already-deployed core.
 * @dev Baseline refs: sec. 28 (jury lifecycle), sec. 29 (randomness through an
 *      adapter), sec. 31 (fallback committee), sec. 45 (multisig control).
 *
 *      Separate from `DeployCore` because the two have different lifetimes: the
 *      core is deployed once and the dispute layer may be redeployed against it
 *      as the court evolves. Every core address is read from the environment
 *      rather than deployed here, so this script can never quietly stand up a
 *      second hub and point the court at the wrong one.
 *
 *      ## What this script refuses to do
 *
 *      It will not accept an EOA as the fallback committee. sec. 31 asks for a
 *      3-of-5 Safe; a single key holding the power to end any failed dispute is
 *      the centralization this phase is supposed to bound, and the check is here
 *      rather than in a runbook because a runbook cannot revert.
 *
 *      Roles are not granted here. `DISPUTE_COURT_ROLE` on the hub and the pool,
 *      and `REFERRAL_REPORTER_ROLE` on the referral registry, are all held by the
 *      admin multisig and granted deliberately after the addresses have been
 *      checked — see the runbook printed at the end.
 */
contract DeployDisputeScript is Script {
    error AddressMissing(string what);
    error WrongChain(uint256 expected, uint256 actual);
    error CommitteeMustBeAContract(address committee);

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        uint256 expectedChainId = vm.envOr("EXPECTED_CHAIN_ID", uint256(0));
        if (expectedChainId != 0 && block.chainid != expectedChainId) {
            revert WrongChain(expectedChainId, block.chainid);
        }

        ProtocolAccessManager accessManager = ProtocolAccessManager(_required("ACCESS_MANAGER"));
        ProtocolConfig config = ProtocolConfig(_required("PROTOCOL_CONFIG"));
        DeliveryHub hub = DeliveryHub(_required("DELIVERY_HUB"));
        Referral referral = Referral(payable(vm.envOr("REFERRAL", address(0))));

        // The Pyth Entropy contract on this chain (sec. 29). No blockhash
        // fallback: the baseline rules it out explicitly, so a missing address
        // stops the deployment rather than degrading it.
        address entropy = _required("PYTH_ENTROPY");

        // sec. 31: a Safe, not a key. A contract is the weakest check that can
        // be made on chain, and it is still worth making — it catches the
        // deployment that pastes in an EOA by mistake.
        address safe = _required("FALLBACK_SAFE");
        if (safe.code.length == 0) revert CommitteeMustBeAContract(safe);

        vm.startBroadcast(deployerKey);

        PythEntropyAdapter randomness = new PythEntropyAdapter(IEntropyV2(entropy));
        JurorPool pool = new JurorPool(accessManager, config);
        FallbackCommittee committee = new FallbackCommittee(accessManager, safe);
        DisputeCourt court = new DisputeCourt(
            accessManager, config, pool, IRandomnessAdapter(address(randomness)), referral, hub, committee
        );

        vm.stopBroadcast();

        // A freshly deployed court owes nothing and holds nothing. Either being
        // untrue means it is not fresh, and pointing users at it would mix their
        // bonds with somebody else's.
        if (pool.totalStaked() != 0) revert AddressMissing("pool stake");
        if (address(pool).balance != 0) revert AddressMissing("pool balance");
        if (court.totalOwed() != 0) revert AddressMissing("court liabilities");
        if (address(court).balance != 0) revert AddressMissing("court balance");
        if (court.nextDisputeId() != 0) revert AddressMissing("court disputes");

        _report(address(randomness), address(pool), address(committee), address(court), address(hub), safe);
    }

    function _required(string memory key) internal view returns (address value) {
        value = vm.envOr(key, address(0));
        if (value == address(0)) revert AddressMissing(key);
    }

    function _report(address randomness, address pool, address committee, address court, address hub, address safe)
        internal
        view
    {
        console2.log("");
        console2.log("=== MONOSFER dispute layer (P4) ===");
        console2.log("chainId:              ", block.chainid);
        console2.log("PythEntropyAdapter:   ", randomness);
        console2.log("JurorPool:            ", pool);
        console2.log("FallbackCommittee:    ", committee);
        console2.log("DisputeCourt:         ", court);
        console2.log("  committee Safe:     ", safe);
        console2.log("");
        console2.log("Roles the admin multisig must now grant:");
        console2.log("  DISPUTE_COURT_ROLE      -> ", court);
        console2.log("    (needed on JurorPool, on the hub, and on FallbackCommittee)");
        console2.log("  REFERRAL_REPORTER_ROLE  -> ", court);
        console2.log("");
        console2.log("Grant DISPUTE_COURT_ROLE only to the court address above, never to an EOA.");
        console2.log("The hub at", hub, "must be the one the court was built against.");
        console2.log("");
        console2.log("sec. 31: monitor every use of the fallback committee. It is a");
        console2.log("last-resort liveness mechanism, not routine dispute administration.");
    }
}
