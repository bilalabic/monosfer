// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {ProtocolAccessManager} from "../../src/v1/access/ProtocolAccessManager.sol";
import {ProtocolConfig} from "../../src/v1/config/ProtocolConfig.sol";
import {SettlementVault} from "../../src/v1/vault/SettlementVault.sol";
import {CourierRegistry} from "../../src/v1/registry/CourierRegistry.sol";
import {DeliveryHub} from "../../src/v1/hub/DeliveryHub.sol";
import {JurorPool} from "../../src/v1/dispute/JurorPool.sol";
import {DisputeCourt} from "../../src/v1/dispute/DisputeCourt.sol";
import {FallbackCommittee} from "../../src/v1/dispute/FallbackCommittee.sol";

/**
 * @title VerifyDeployment
 * @notice Audits a deployment that is already live, after its roles were granted.
 * @dev Baseline refs: sec. 32.11 (no single EOA controls critical permissions),
 *      sec. 45 (multisig for critical control), sec. 31 (the committee is a Safe),
 *      invariant sec. 33-1 (the vault is solvent).
 *
 *      ## Why this exists separately from the deploy scripts
 *
 *      `DeployCore` checks its *inputs*: that the role addresses it was handed
 *      are distinct and non-zero. It cannot check anything more, because at that
 *      point no role has been granted — the admin multisig does that afterwards,
 *      deliberately, so the deployer key never holds an operational role.
 *
 *      That leaves a window nothing was watching: between "contracts exist" and
 *      "contracts are wired", every mistake is silent. A role granted to the
 *      wrong address, a role forgotten, a hub pointed at last week's registry,
 *      a committee pointed at somebody's EOA — each one deploys cleanly and
 *      fails later, in production, as something that looks like a different bug.
 *
 *      So this reads the live system and refuses to pass on any of them. It
 *      broadcasts nothing and can be run against any deployment at any time.
 *
 *      ## What it cannot check
 *
 *      `AccessControlDefaultAdminRules` does not enumerate its members, so
 *      "nobody else holds this role" is not answerable on chain. What is
 *      answerable is "these specific addresses do or do not hold it", so the
 *      expected holders are supplied and checked both ways: every intended
 *      holder has the role, and every address that must *not* have it does not.
 *      An unknown fourth party holding a role would go unseen, which is why the
 *      grant transactions themselves stay reviewable in the manifest.
 */
contract VerifyDeploymentScript is Script {
    error Missing(string what);
    error NotAContract(string what, address who);
    error RoleMissing(string role, address who);
    error RoleHeldWrongly(string role, address who);
    error CriticalRolesShared(string roleA, string roleB, address who);
    error Insolvent(string what, uint256 owed, uint256 held);
    error Misconfigured(string what, address expected, address actual);

    struct Wiring {
        ProtocolAccessManager manager;
        ProtocolConfig config;
        SettlementVault vault;
        CourierRegistry registry;
        DeliveryHub hub;
        JurorPool pool;
        DisputeCourt court;
        FallbackCommittee committee;
    }

    function run() external view {
        Wiring memory w = _load();

        _checkCode(w);
        _checkPointers(w);
        _checkOperationalRoles(w);
        _checkHumanRoles(w);
        _checkSolvency(w);
        _checkCommittee(w);

        console2.log("");
        console2.log("=== deployment verified ===");
        console2.log("chainId:          ", block.chainid);
        console2.log("code present:      8 contracts");
        console2.log("pointers agree:    11");
        console2.log("machine roles:     5 held, 8 correctly absent");
        console2.log("operator roles:    checked and pairwise distinct");
        console2.log("vault + court:     solvent");
        console2.log("committee:         a contract, not an EOA");
    }

    // ---------------------------------------------------------------- load

    function _load() internal view returns (Wiring memory w) {
        w.manager = ProtocolAccessManager(_req("ACCESS_MANAGER"));
        w.config = ProtocolConfig(_req("PROTOCOL_CONFIG"));
        w.vault = SettlementVault(payable(_req("SETTLEMENT_VAULT")));
        w.registry = CourierRegistry(payable(_req("COURIER_REGISTRY")));
        w.hub = DeliveryHub(_req("DELIVERY_HUB"));
        w.pool = JurorPool(payable(_req("JUROR_POOL")));
        w.court = DisputeCourt(payable(_req("DISPUTE_COURT")));
        w.committee = FallbackCommittee(_req("FALLBACK_COMMITTEE"));
    }

    function _req(string memory key) internal view returns (address v) {
        v = vm.envOr(key, address(0));
        if (v == address(0)) revert Missing(key);
    }

    // --------------------------------------------------------------- code

    /// @dev A deployment whose addresses hold no code is a typo, not a system.
    function _checkCode(Wiring memory w) internal view {
        _hasCode("ACCESS_MANAGER", address(w.manager));
        _hasCode("PROTOCOL_CONFIG", address(w.config));
        _hasCode("SETTLEMENT_VAULT", address(w.vault));
        _hasCode("COURIER_REGISTRY", address(w.registry));
        _hasCode("DELIVERY_HUB", address(w.hub));
        _hasCode("JUROR_POOL", address(w.pool));
        _hasCode("DISPUTE_COURT", address(w.court));
        _hasCode("FALLBACK_COMMITTEE", address(w.committee));
    }

    function _hasCode(string memory what, address who) internal view {
        if (who.code.length == 0) revert NotAContract(what, who);
    }

    // ------------------------------------------------------------ pointers

    /**
     * @dev Every contract naming another is checked against the manifest. This
     *      is the check that catches a hub left pointing at the previous
     *      deployment's registry — the mistake that looks like nothing until
     *      settlement reaches for collateral that was never reserved.
     */
    function _checkPointers(Wiring memory w) internal view {
        _same("hub.registry", address(w.registry), address(w.hub.registry()));
        _same("hub.vault", address(w.vault), address(w.hub.vault()));
        _same("hub.config", address(w.config), address(w.hub.config()));
        _same("hub.accessManager", address(w.manager), address(w.hub.accessManager()));

        _same("registry.vault", address(w.vault), address(w.registry.vault()));
        _same("registry.config", address(w.config), address(w.registry.config()));

        _same("court.hub", address(w.hub), address(w.court.hub()));
        _same("court.jurors", address(w.pool), address(w.court.jurors()));
        _same("court.committee", address(w.committee), address(w.court.committee()));
        _same("court.config", address(w.config), address(w.court.config()));

        _same("pool.config", address(w.config), address(w.pool.config()));
    }

    function _same(string memory what, address expected, address actual) internal pure {
        if (expected != actual) revert Misconfigured(what, expected, actual);
    }

    // ------------------------------------------------------ machine roles

    /**
     * @dev The roles contracts hold over one another. Each is checked positively
     *      (the contract that needs it has it) and negatively (the deployer does
     *      not), because a role granted to the deploying key is the sec. 32.11
     *      finding this whole phase exists to remove.
     */
    function _checkOperationalRoles(Wiring memory w) internal view {
        address deployer = vm.envOr("DEPLOYER", address(0));

        _hasRole(w, "VAULT_CONTROLLER_ROLE", w.manager.VAULT_CONTROLLER_ROLE(), address(w.registry));
        _hasRole(w, "VAULT_CONTROLLER_ROLE", w.manager.VAULT_CONTROLLER_ROLE(), address(w.hub));
        _hasRole(w, "REGISTRY_CONTROLLER_ROLE", w.manager.REGISTRY_CONTROLLER_ROLE(), address(w.hub));
        _hasRole(w, "REPUTATION_REPORTER_ROLE", w.manager.REPUTATION_REPORTER_ROLE(), address(w.hub));
        _hasRole(w, "DISPUTE_COURT_ROLE", w.manager.DISPUTE_COURT_ROLE(), address(w.court));

        if (deployer != address(0)) {
            _lacksRole(w, "VAULT_CONTROLLER_ROLE", w.manager.VAULT_CONTROLLER_ROLE(), deployer);
            _lacksRole(w, "REGISTRY_CONTROLLER_ROLE", w.manager.REGISTRY_CONTROLLER_ROLE(), deployer);
            _lacksRole(w, "DISPUTE_COURT_ROLE", w.manager.DISPUTE_COURT_ROLE(), deployer);
            _lacksRole(w, "CONFIG_ADMIN_ROLE", w.manager.CONFIG_ADMIN_ROLE(), deployer);
            _lacksRole(w, "EMERGENCY_ROLE", w.manager.EMERGENCY_ROLE(), deployer);
            _lacksRole(w, "TREASURER_ROLE", w.manager.TREASURER_ROLE(), deployer);
        }

        // The court must never hold power over the vault or the registry
        // directly: it speaks to the hub, and the hub owns the money.
        _lacksRole(w, "VAULT_CONTROLLER_ROLE", w.manager.VAULT_CONTROLLER_ROLE(), address(w.court));
        _lacksRole(w, "REGISTRY_CONTROLLER_ROLE", w.manager.REGISTRY_CONTROLLER_ROLE(), address(w.court));
    }

    // -------------------------------------------------------- human roles

    /**
     * @dev sec. 32.11 and sec. 45: the operator roles, and the separations that
     *      make them mean something. Checked here against the live grants rather
     *      than against what the deploy script was told, because those are two
     *      different facts and only one of them is what the chain believes.
     */
    function _checkHumanRoles(Wiring memory w) internal view {
        address configAdmin = vm.envOr("CONFIG_ADMIN", address(0));
        address emergency = vm.envOr("EMERGENCY_ADMIN", address(0));
        address signerAdmin = vm.envOr("SIGNER_ADMIN", address(0));
        address treasurer = vm.envOr("TREASURER", address(0));

        // Separation is checked first, and on the live grants rather than on
        // the addresses we were handed. A key holding two critical roles is the
        // more serious finding of the two, and reporting it as a missing role
        // would send whoever reads the failure looking in the wrong place.
        //
        // Pausing and unpausing are split on purpose (sec. 45); one key holding
        // both collapses the split. Same for config against emergency, and for
        // signer rotation against config, which is timelocked while rotation is
        // not — sharing a key there would give the timelock a bypass.
        _notBoth(w, "CONFIG_ADMIN_ROLE", w.manager.CONFIG_ADMIN_ROLE(), "EMERGENCY_ROLE", w.manager.EMERGENCY_ROLE());
        _notBoth(
            w, "CONFIG_ADMIN_ROLE", w.manager.CONFIG_ADMIN_ROLE(), "SIGNER_ADMIN_ROLE", w.manager.SIGNER_ADMIN_ROLE()
        );
        _notBoth(w, "CONFIG_ADMIN_ROLE", w.manager.CONFIG_ADMIN_ROLE(), "TREASURER_ROLE", w.manager.TREASURER_ROLE());
        _notBoth(w, "EMERGENCY_ROLE", w.manager.EMERGENCY_ROLE(), "SIGNER_ADMIN_ROLE", w.manager.SIGNER_ADMIN_ROLE());
        _notBoth(w, "EMERGENCY_ROLE", w.manager.EMERGENCY_ROLE(), "TREASURER_ROLE", w.manager.TREASURER_ROLE());
        _notBoth(w, "SIGNER_ADMIN_ROLE", w.manager.SIGNER_ADMIN_ROLE(), "TREASURER_ROLE", w.manager.TREASURER_ROLE());

        if (configAdmin != address(0)) {
            _hasRole(w, "CONFIG_ADMIN_ROLE", w.manager.CONFIG_ADMIN_ROLE(), configAdmin);
        }
        if (emergency != address(0)) {
            _hasRole(w, "EMERGENCY_ROLE", w.manager.EMERGENCY_ROLE(), emergency);
        }
        if (signerAdmin != address(0)) {
            _hasRole(w, "SIGNER_ADMIN_ROLE", w.manager.SIGNER_ADMIN_ROLE(), signerAdmin);
        }
        if (treasurer != address(0)) {
            _hasRole(w, "TREASURER_ROLE", w.manager.TREASURER_ROLE(), treasurer);
        }

        // And the two signing services must not be one key, or a single
        // compromise forges both the coverage price and the proof of delivery.
        address quoteSigner = w.config.riskQuoteSigner();
        address podSigner = w.config.podAttestationSigner();
        if (quoteSigner == podSigner) {
            revert CriticalRolesShared("RISK_QUOTE_SIGNER", "POD_ATTESTATION_SIGNER", quoteSigner);
        }
    }

    /**
     * @dev Asks the chain rather than the operator: does any of the addresses we
     *      know about hold both of these roles? Every candidate is tried, so a
     *      key that quietly acquired a second critical role after deployment is
     *      caught even though it was never named as that role's holder.
     */
    function _notBoth(Wiring memory w, string memory nameA, bytes32 roleA, string memory nameB, bytes32 roleB)
        internal
        view
    {
        address[5] memory candidates = [
            vm.envOr("CONFIG_ADMIN", address(0)),
            vm.envOr("EMERGENCY_ADMIN", address(0)),
            vm.envOr("SIGNER_ADMIN", address(0)),
            vm.envOr("TREASURER", address(0)),
            vm.envOr("DEPLOYER", address(0))
        ];
        for (uint256 i = 0; i < candidates.length; i++) {
            address who = candidates[i];
            if (who == address(0)) continue;
            if (w.manager.hasRole(roleA, who) && w.manager.hasRole(roleB, who)) {
                revert CriticalRolesShared(nameA, nameB, who);
            }
        }
    }

    // --------------------------------------------------------- solvency

    /// @dev Invariant sec. 33-1, read off the live chain rather than assumed.
    function _checkSolvency(Wiring memory w) internal view {
        uint256 owed = w.vault.totalLiabilities();
        if (address(w.vault).balance < owed) revert Insolvent("vault", owed, address(w.vault).balance);

        uint256 courtOwed = w.court.totalOwed();
        if (address(w.court).balance < courtOwed) revert Insolvent("court", courtOwed, address(w.court).balance);
    }

    // -------------------------------------------------------- committee

    /**
     * @dev sec. 31 asks for a 3-of-5 Safe. The threshold itself lives inside the
     *      Safe and is not readable through this interface, but "is it a
     *      contract at all" is, and it is the check that catches the deployment
     *      that pasted in somebody's EOA.
     */
    function _checkCommittee(Wiring memory w) internal view {
        address safe = w.committee.safe();
        if (safe == address(0)) revert Missing("committee safe");
        if (safe.code.length == 0) revert NotAContract("committee safe", safe);
    }

    // ---------------------------------------------------------- plumbing

    function _hasRole(Wiring memory w, string memory name, bytes32 role, address who) internal view {
        if (!w.manager.hasRole(role, who)) revert RoleMissing(name, who);
    }

    function _lacksRole(Wiring memory w, string memory name, bytes32 role, address who) internal view {
        if (w.manager.hasRole(role, who)) revert RoleHeldWrongly(name, who);
    }
}
