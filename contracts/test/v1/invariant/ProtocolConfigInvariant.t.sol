// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {ProtocolAccessManager} from "../../../src/v1/access/ProtocolAccessManager.sol";
import {ProtocolConfig} from "../../../src/v1/config/ProtocolConfig.sol";
import {BaselineParams} from "../../../src/v1/config/BaselineParams.sol";

/**
 * @notice Drives ProtocolConfig and ProtocolAccessManager with randomised callers
 *         and randomised parameter values.
 * @dev Deliberately calls from unauthorised addresses too. Reverts are expected and
 *      swallowed; the point is that no sequence of calls, authorised or not, can
 *      break the invariants asserted by the test contract.
 */
contract ConfigHandler is Test {
    ProtocolAccessManager public immutable manager;
    ProtocolConfig public immutable config;

    address public immutable configAdmin;
    address public immutable signerAdmin;
    address public immutable emergency;

    uint64 public maxVersionSeen;
    uint256 public executedChanges;

    constructor(
        ProtocolAccessManager manager_,
        ProtocolConfig config_,
        address configAdmin_,
        address signerAdmin_,
        address emergency_
    ) {
        manager = manager_;
        config = config_;
        configAdmin = configAdmin_;
        signerAdmin = signerAdmin_;
        emergency = emergency_;
        maxVersionSeen = config_.configVersion();
    }

    function _actor(uint256 seed) internal view returns (address) {
        uint256 pick = seed % 4;
        if (pick == 0) return configAdmin;
        if (pick == 1) return signerAdmin;
        if (pick == 2) return emergency;
        return address(uint160(uint256(keccak256(abi.encode(seed)))));
    }

    /**
     * @notice Propose a parameter set that is usually valid.
     * @dev Values are bounded into their legal ranges on purpose. With raw fuzz
     *      words almost every proposal is rejected, the config never changes, and
     *      every other invariant then holds vacuously. Bounding keeps the
     *      authorised path reachable; `proposeWild` below still exercises
     *      rejection.
     */
    function propose(uint256 actorSeed, uint16 feeBps, uint16 c1, uint16 c2, uint16 c3, uint8 custody) external {
        ProtocolConfig.Params memory p = BaselineParams.baseline();
        p.protocolFeeBps = uint16(bound(feeBps, 0, config.MAX_PROTOCOL_FEE_BPS()));

        // Draw three coverage values then sort them, so tier ordering holds.
        uint16 a = uint16(bound(c1, 0, config.MAX_COVERAGE_BPS()));
        uint16 b = uint16(bound(c2, 0, config.MAX_COVERAGE_BPS()));
        uint16 c = uint16(bound(c3, 0, config.MAX_COVERAGE_BPS()));
        (a, b) = a <= b ? (a, b) : (b, a);
        (b, c) = b <= c ? (b, c) : (c, b);
        (a, b) = a <= b ? (a, b) : (b, a);
        p.coverageBpsR1 = a;
        p.coverageBpsR2 = b;
        p.coverageBpsR3 = c;

        p.maxActiveCustody = uint8(bound(custody, config.MIN_ACTIVE_CUSTODY(), config.MAX_ACTIVE_CUSTODY()));

        vm.prank(_actor(actorSeed));
        try config.proposeParams(p) {} catch {}
    }

    /// @notice Propose with unbounded values; these should be rejected.
    function proposeWild(uint256 actorSeed, uint16 feeBps, uint16 c1, uint16 c2, uint16 c3, uint8 custody) external {
        ProtocolConfig.Params memory p = BaselineParams.baseline();
        p.protocolFeeBps = feeBps;
        p.coverageBpsR1 = c1;
        p.coverageBpsR2 = c2;
        p.coverageBpsR3 = c3;
        p.maxActiveCustody = custody;

        vm.prank(_actor(actorSeed));
        try config.proposeParams(p) {} catch {}
    }

    function execute(uint256 actorSeed, uint32 warpBy) external {
        // Half the draws clear the 2-day timelock, half do not.
        vm.warp(block.timestamp + (warpBy % 4 days));
        vm.prank(_actor(actorSeed));
        try config.executeParams() {
            executedChanges++;
        } catch {}
        _recordVersion();
    }

    function cancel(uint256 actorSeed) external {
        vm.prank(_actor(actorSeed));
        try config.cancelParamsProposal() {} catch {}
    }

    function rotateQuoteSigner(uint256 actorSeed, address newSigner) external {
        vm.prank(_actor(actorSeed));
        try config.rotateRiskQuoteSigner(newSigner) {} catch {}
    }

    function proposeTreasury(uint256 actorSeed, address newTreasury) external {
        vm.prank(_actor(actorSeed));
        try config.proposeTreasury(newTreasury) {} catch {}
    }

    function pauseOrUnpause(uint256 actorSeed, bool doPause) external {
        address actor = _actor(actorSeed);
        vm.prank(actor);
        if (doPause) {
            try manager.pause() {} catch {}
        } else {
            try manager.scheduleUnpause() {} catch {}
            vm.prank(actor);
            try manager.unpause() {} catch {}
        }
    }

    function grantRole(uint256 actorSeed, uint256 roleSeed, address target) external {
        bytes32 role = roleSeed % 2 == 0 ? manager.CONFIG_ADMIN_ROLE() : manager.EMERGENCY_ROLE();
        vm.prank(_actor(actorSeed));
        try manager.grantRole(role, target) {} catch {}
    }

    function _recordVersion() internal {
        uint64 current = config.configVersion();
        if (current > maxVersionSeen) maxVersionSeen = current;
    }
}

contract ProtocolConfigInvariantTest is StdInvariant, Test {
    ProtocolAccessManager internal manager;
    ProtocolConfig internal config;
    ConfigHandler internal handler;

    address internal admin = address(0xA11CE);
    address internal configAdmin = address(0xC0FFEE);
    address internal signerAdmin = address(0x5165);
    address internal emergency = address(0xE4E4);

    function setUp() public {
        manager = new ProtocolAccessManager(3 days, admin);
        vm.startPrank(admin);
        manager.grantRole(manager.CONFIG_ADMIN_ROLE(), configAdmin);
        manager.grantRole(manager.SIGNER_ADMIN_ROLE(), signerAdmin);
        manager.grantRole(manager.EMERGENCY_ROLE(), emergency);
        vm.stopPrank();

        config = new ProtocolConfig(
            manager, 2 days, BaselineParams.baseline(), address(0x7EA5), address(0x0001), address(0x0002)
        );

        handler = new ConfigHandler(manager, config, configAdmin, signerAdmin, emergency);
        targetContract(address(handler));
    }

    /// @dev Baseline invariant sec.33-15: admin actions stay inside configured bounds.
    function invariant_ParamsAlwaysWithinBounds() public view {
        ProtocolConfig.Params memory p = config.params();

        assertLe(p.protocolFeeBps, config.MAX_PROTOCOL_FEE_BPS(), "fee above ceiling");
        assertLe(p.coverageBpsR3, config.MAX_COVERAGE_BPS(), "coverage above 100%");
        assertLe(p.coverageBpsR1, p.coverageBpsR2, "R1 must not exceed R2");
        assertLe(p.coverageBpsR2, p.coverageBpsR3, "R2 must not exceed R3");

        assertGe(p.maxActiveCustody, config.MIN_ACTIVE_CUSTODY());
        assertLe(p.maxActiveCustody, config.MAX_ACTIVE_CUSTODY());

        assertGe(p.challengeWindow, config.MIN_CHALLENGE_WINDOW());
        assertLe(p.challengeWindow, config.MAX_CHALLENGE_WINDOW());
        assertGe(p.fundingWindow, config.MIN_FUNDING_WINDOW());
        assertLe(p.fundingWindow, config.MAX_FUNDING_WINDOW());

        assertGe(p.courierBaseDeposit, config.MIN_COURIER_DEPOSIT());
        assertLe(p.courierBaseDeposit, config.MAX_COURIER_DEPOSIT());

        // Juror economics can never invert (sec.27).
        assertLe(p.jurorLockPerCase, p.minJurorStake, "lock above stake");
        assertLe(p.nonRevealSlash, p.jurorLockPerCase, "slash above lock");

        // Jury rounds stay odd and strictly increasing (sec.28).
        assertTrue(p.juryFirstSize % 2 == 1, "first round must be odd");
        assertTrue(p.juryAppeal1Size % 2 == 1, "appeal 1 must be odd");
        assertTrue(p.juryAppeal2Size % 2 == 1, "appeal 2 must be odd");
        assertLt(p.juryFirstSize, p.juryAppeal1Size);
        assertLt(p.juryAppeal1Size, p.juryAppeal2Size);
    }

    /// @dev Version is monotonic: it must never move backwards.
    function invariant_VersionNeverDecreases() public view {
        assertGe(config.configVersion(), handler.maxVersionSeen(), "config version went backwards");
        assertGe(config.configVersion(), 1, "version must start at 1");
    }

    /// @dev Critical addresses can never become the zero address.
    function invariant_CriticalAddressesNeverZero() public view {
        assertTrue(config.treasury() != address(0), "treasury zeroed");
        assertTrue(config.riskQuoteSigner() != address(0), "quote signer zeroed");
        assertTrue(config.podAttestationSigner() != address(0), "pod signer zeroed");
    }

    /// @dev No handler actor may acquire a role it was not granted in setUp.
    function invariant_NoRoleEscalation() public view {
        assertFalse(manager.hasRole(manager.EMERGENCY_ROLE(), configAdmin), "config admin gained emergency");
        assertFalse(manager.hasRole(manager.CONFIG_ADMIN_ROLE(), emergency), "emergency gained config");
        assertFalse(manager.hasRole(manager.CONFIG_ADMIN_ROLE(), signerAdmin), "signer admin gained config");
        assertFalse(manager.hasRole(manager.DEFAULT_ADMIN_ROLE(), configAdmin), "config admin gained default admin");
    }

    /**
     * @dev Guards the suite itself. If the handler could never reach the
     *      authorised path, every invariant above would hold vacuously and prove
     *      nothing. This drives the handler deterministically to show a real
     *      config change is reachable through it.
     *
     *      Written as a unit test rather than an invariant on purpose: each
     *      invariant run restarts from the post-setUp state, so requiring every
     *      random run to land on the authorised path would be a property of the
     *      fuzzer's luck, not of the contract.
     */
    function test_HandlerCanReachExecution() public {
        // actorSeed % 4 == 0 selects configAdmin.
        handler.propose(0, 300, 1_000, 2_000, 3_000, 1);
        handler.execute(0, uint32(3 days)); // clears the 2-day timelock

        assertGt(handler.executedChanges(), 0, "handler cannot reach an executed change");
        assertEq(config.configVersion(), 2, "version must advance");
        assertEq(config.protocolFeeBps(), 300, "proposed value must be applied");
    }

    /// @dev Unauthorised or out-of-bounds handler paths must leave state untouched.
    function test_HandlerWildProposalsAreRejected() public {
        uint64 versionBefore = config.configVersion();
        handler.proposeWild(0, type(uint16).max, 9_000, 1_000, 500, 0);
        handler.execute(0, uint32(3 days));
        assertEq(config.configVersion(), versionBefore, "invalid proposal must not apply");
    }

    /// @dev Immutable wiring can never drift.
    function invariant_ImmutableWiringHolds() public view {
        assertEq(address(config.accessManager()), address(manager));
        assertEq(config.configTimelock(), 2 days);
    }
}
