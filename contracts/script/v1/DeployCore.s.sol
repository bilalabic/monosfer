// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ProtocolAccessManager} from "../../src/v1/access/ProtocolAccessManager.sol";
import {ProtocolConfig} from "../../src/v1/config/ProtocolConfig.sol";
import {SettlementVault} from "../../src/v1/vault/SettlementVault.sol";
import {BaselineParams} from "../../src/v1/config/BaselineParams.sol";
import {CourierRegistry} from "../../src/v1/registry/CourierRegistry.sol";

/**
 * @title DeployCore
 * @notice Deploys the V1 governance core: ProtocolAccessManager + ProtocolConfig.
 * @dev Baseline refs: sec. 32.11 (no single EOA controls critical permissions),
 *      sec. 45 (multisig for critical control), sec. 48 (initial testnet parameters).
 *
 *      Role holders are supplied per-role through the environment rather than
 *      defaulting to the deployer. The legacy scripts assign treasury, reward
 *      pool and every owner to one deployer EOA; reproducing that here would
 *      recreate the exact finding this phase exists to remove.
 *
 *      Post-deploy assertions run inside the broadcast, so a misconfigured
 *      deployment fails loudly instead of silently shipping a single-key setup.
 */
contract DeployCoreScript is Script {
    error RoleAddressMissing(string role);
    error CriticalRolesShareAnAddress(string roleA, string roleB);
    error WrongChain(uint256 expected, uint256 actual);
    error VaultNotEmpty(string what);

    struct RoleSet {
        address defaultAdmin;
        address configAdmin;
        address emergency;
        address signerAdmin;
        address treasurer;
        address treasury;
        address riskQuoteSigner;
        address podAttestationSigner;
    }

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        // Refuse to run against an unexpected network. The legacy Solidity
        // scripts had no chain guard; only the shell wrapper checked.
        uint256 expectedChainId = vm.envOr("EXPECTED_CHAIN_ID", uint256(0));
        if (expectedChainId != 0 && block.chainid != expectedChainId) {
            revert WrongChain(expectedChainId, block.chainid);
        }

        RoleSet memory roles = _loadRoles();
        _assertRolesSeparated(roles);

        uint48 adminDelay = uint48(vm.envOr("ADMIN_TRANSFER_DELAY", uint256(3 days)));
        uint64 configTimelock = uint64(vm.envOr("CONFIG_TIMELOCK", uint256(2 days)));

        vm.startBroadcast(deployerKey);

        ProtocolAccessManager accessManager = new ProtocolAccessManager(adminDelay, roles.defaultAdmin);
        ProtocolConfig config = new ProtocolConfig(
            accessManager,
            configTimelock,
            BaselineParams.baseline(),
            roles.treasury,
            roles.riskQuoteSigner,
            roles.podAttestationSigner
        );

        SettlementVault vault = new SettlementVault(accessManager);
        CourierRegistry registry = new CourierRegistry(accessManager, config, vault);

        vm.stopBroadcast();

        // A freshly deployed vault must owe nothing and hold nothing. If either
        // is untrue the deployment is already inconsistent and must not ship.
        if (vault.totalLiabilities() != 0) revert VaultNotEmpty("liabilities");
        if (address(vault).balance != 0) revert VaultNotEmpty("balance");
        if (registry.totalStaked() != 0) revert VaultNotEmpty("registry stake");
        if (address(registry).balance != 0) revert VaultNotEmpty("registry balance");

        _report(accessManager, config, vault, registry, roles);
    }

    function _loadRoles() internal view returns (RoleSet memory roles) {
        roles.defaultAdmin = _requireAddress("DEFAULT_ADMIN");
        roles.configAdmin = _requireAddress("CONFIG_ADMIN");
        roles.emergency = _requireAddress("EMERGENCY_ADMIN");
        roles.signerAdmin = _requireAddress("SIGNER_ADMIN");
        roles.treasurer = _requireAddress("TREASURER");
        roles.treasury = _requireAddress("TREASURY");
        roles.riskQuoteSigner = _requireAddress("RISK_QUOTE_SIGNER");
        roles.podAttestationSigner = _requireAddress("POD_ATTESTATION_SIGNER");
    }

    function _requireAddress(string memory key) internal view returns (address value) {
        value = vm.envOr(key, address(0));
        if (value == address(0)) revert RoleAddressMissing(key);
    }

    /**
     * @dev The separations that matter, and why:
     *      - defaultAdmin vs configAdmin: the admin that grants roles must not
     *        also be the day-to-day config operator.
     *      - configAdmin vs emergency: pausing and unpausing are deliberately
     *        split (sec. 45). One key holding both collapses that split.
     *      - signerAdmin vs configAdmin: signer rotation is immediate while
     *        config is timelocked; sharing a key would give the timelock a
     *        bypass-shaped neighbour.
     */
    function _assertRolesSeparated(RoleSet memory roles) internal pure {
        if (roles.defaultAdmin == roles.configAdmin) {
            revert CriticalRolesShareAnAddress("DEFAULT_ADMIN", "CONFIG_ADMIN");
        }
        if (roles.configAdmin == roles.emergency) {
            revert CriticalRolesShareAnAddress("CONFIG_ADMIN", "EMERGENCY_ADMIN");
        }
        if (roles.configAdmin == roles.signerAdmin) {
            revert CriticalRolesShareAnAddress("CONFIG_ADMIN", "SIGNER_ADMIN");
        }
        if (roles.defaultAdmin == roles.emergency) {
            revert CriticalRolesShareAnAddress("DEFAULT_ADMIN", "EMERGENCY_ADMIN");
        }
        if (roles.riskQuoteSigner == roles.podAttestationSigner) {
            revert CriticalRolesShareAnAddress("RISK_QUOTE_SIGNER", "POD_ATTESTATION_SIGNER");
        }
    }

    function _report(
        ProtocolAccessManager accessManager,
        ProtocolConfig config,
        SettlementVault vault,
        CourierRegistry registry,
        RoleSet memory roles
    ) internal pure {
        console2.log("ProtocolAccessManager:", address(accessManager));
        console2.log("ProtocolConfig:       ", address(config));
        console2.log("SettlementVault:      ", address(vault));
        console2.log("CourierRegistry:      ", address(registry));
        console2.log("default admin:        ", roles.defaultAdmin);
        console2.log("config admin:         ", roles.configAdmin);
        console2.log("emergency:            ", roles.emergency);
        console2.log("signer admin:         ", roles.signerAdmin);
        console2.log("treasury:             ", roles.treasury);
        console2.log("");
        console2.log("Roles are NOT granted by this script. The default admin must grant");
        console2.log("CONFIG_ADMIN / EMERGENCY / SIGNER_ADMIN / TREASURER from its own");
        console2.log("multisig, so no deployer key ever holds them.");
        console2.log("");
        console2.log("VAULT_CONTROLLER_ROLE must go to protocol CONTRACTS only");
        console2.log("(DeliveryHub in P1, DisputeCourt in P4), never to an EOA.");
        console2.log("The registry itself needs VAULT_CONTROLLER_ROLE: it moves");
        console2.log("courier stake inside the vault. Grant it after deployment.");
    }
}
