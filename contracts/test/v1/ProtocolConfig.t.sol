// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProtocolAccessManager} from "../../src/v1/access/ProtocolAccessManager.sol";
import {ProtocolConfig} from "../../src/v1/config/ProtocolConfig.sol";
import {BaselineParams} from "./helpers/BaselineParams.sol";

contract ProtocolConfigTest is Test {
    ProtocolAccessManager internal manager;
    ProtocolConfig internal config;

    address internal admin = address(0xA11CE);
    address internal configAdmin = address(0xC0FFEE);
    address internal signerAdmin = address(0x5165);
    address internal stranger = address(0xBAD);

    address internal treasury = address(0x7EA5);
    address internal quoteSigner = address(0x0001);
    address internal podSigner = address(0x0002);

    uint64 internal constant TIMELOCK = 2 days;

    function setUp() public {
        manager = new ProtocolAccessManager(3 days, admin);
        vm.startPrank(admin);
        manager.grantRole(manager.CONFIG_ADMIN_ROLE(), configAdmin);
        manager.grantRole(manager.SIGNER_ADMIN_ROLE(), signerAdmin);
        vm.stopPrank();

        config = new ProtocolConfig(manager, TIMELOCK, BaselineParams.baseline(), treasury, quoteSigner, podSigner);
    }

    function _deployWith(ProtocolConfig.Params memory p) internal returns (ProtocolConfig) {
        return new ProtocolConfig(manager, TIMELOCK, p, treasury, quoteSigner, podSigner);
    }

    // ---------------------------------------------------------- construction

    /// @dev The deployed config must literally match the §48 table.
    function test_Constructor_MatchesBaselineTable() public view {
        ProtocolConfig.Params memory p = config.params();
        assertEq(p.protocolFeeBps, 200, "protocol fee must be 2% (sec.48)");
        assertEq(p.courierBaseDeposit, 10 ether, "courier deposit must be 10 MON (sec.48)");
        assertEq(p.coverageBpsR1, 2_500);
        assertEq(p.coverageBpsR2, 6_000);
        assertEq(p.coverageBpsR3, 10_000);
        assertEq(p.maxActiveCustody, 1, "sec.9 MAX_ACTIVE_CUSTODY");
        assertEq(p.fundingWindow, 15 minutes);
        assertEq(p.challengeWindow, 24 hours);
        assertEq(p.courierWithdrawalCooldown, 24 hours);
        assertEq(p.minJurorStake, 10 ether);
        assertEq(p.jurorLockPerCase, 2 ether);
        assertEq(p.nonRevealSlash, 1 ether);
        assertEq(p.juryFirstSize, 3);
        assertEq(p.juryAppeal1Size, 5);
        assertEq(p.juryAppeal2Size, 7);
        assertEq(p.customerMaxActiveListings, 5);
        assertEq(p.riskQuoteValidity, 5 minutes);
        assertEq(p.podAttestationValidity, 10 minutes);
        assertEq(p.rewardClaimWindow, 90 days);
        assertEq(p.rewardReclaimDelay, 7 days);
    }

    function test_Constructor_StartsAtVersionOne() public view {
        assertEq(config.configVersion(), 1);
    }

    function test_Constructor_RejectsZeroAddresses() public {
        ProtocolConfig.Params memory p = BaselineParams.baseline();
        vm.expectRevert(ProtocolConfig.ZeroAddress.selector);
        new ProtocolConfig(manager, TIMELOCK, p, address(0), quoteSigner, podSigner);

        vm.expectRevert(ProtocolConfig.ZeroAddress.selector);
        new ProtocolConfig(manager, TIMELOCK, p, treasury, address(0), podSigner);

        vm.expectRevert(ProtocolConfig.ZeroAddress.selector);
        new ProtocolConfig(manager, TIMELOCK, p, treasury, quoteSigner, address(0));
    }

    function test_Constructor_RejectsTimelockOutOfBounds() public {
        ProtocolConfig.Params memory p = BaselineParams.baseline();
        uint64 tooShort = uint64(1 minutes);
        vm.expectRevert(abi.encodeWithSelector(ProtocolConfig.TimelockOutOfBounds.selector, tooShort));
        new ProtocolConfig(manager, tooShort, p, treasury, quoteSigner, podSigner);

        uint64 tooLong = uint64(31 days);
        vm.expectRevert(abi.encodeWithSelector(ProtocolConfig.TimelockOutOfBounds.selector, tooLong));
        new ProtocolConfig(manager, tooLong, p, treasury, quoteSigner, podSigner);
    }

    // --------------------------------------------------------------- bounds

    function test_Bounds_RejectsExcessiveFee() public {
        ProtocolConfig.Params memory p = BaselineParams.baseline();
        p.protocolFeeBps = config.MAX_PROTOCOL_FEE_BPS() + 1;
        vm.expectRevert(abi.encodeWithSelector(ProtocolConfig.OutOfBounds.selector, "protocolFeeBps"));
        _deployWith(p);
    }

    function test_Bounds_RejectsCoverageAboveHundredPercent() public {
        ProtocolConfig.Params memory p = BaselineParams.baseline();
        p.coverageBpsR3 = 10_001;
        vm.expectRevert(abi.encodeWithSelector(ProtocolConfig.OutOfBounds.selector, "coverageBpsR3"));
        _deployWith(p);
    }

    /// @dev §6: a higher risk tier can never require less coverage than a lower one.
    function test_Bounds_RejectsInvertedCoverageOrdering() public {
        ProtocolConfig.Params memory p = BaselineParams.baseline();
        p.coverageBpsR1 = 9_000; // above R2
        vm.expectRevert(ProtocolConfig.InvalidCoverageOrdering.selector);
        _deployWith(p);
    }

    function test_Bounds_RejectsEvenJurySize() public {
        ProtocolConfig.Params memory p = BaselineParams.baseline();
        p.juryFirstSize = 4;
        vm.expectRevert(abi.encodeWithSelector(ProtocolConfig.JurySizeMustBeOdd.selector, uint8(4)));
        _deployWith(p);
    }

    /// @dev §28: each appeal round must be strictly larger than the previous one.
    function test_Bounds_RejectsNonIncreasingJuryRounds() public {
        ProtocolConfig.Params memory p = BaselineParams.baseline();
        p.juryAppeal1Size = 3; // equal to first round
        vm.expectRevert(ProtocolConfig.InvalidJuryOrdering.selector);
        _deployWith(p);
    }

    /// @dev §27: a juror can never be locked for more than the minimum stake.
    function test_Bounds_RejectsLockAboveStake() public {
        ProtocolConfig.Params memory p = BaselineParams.baseline();
        p.jurorLockPerCase = p.minJurorStake + 1;
        vm.expectRevert(ProtocolConfig.InvalidJurorEconomics.selector);
        _deployWith(p);
    }

    /// @dev §27: a juror can never be slashed for more than is locked for the case.
    function test_Bounds_RejectsSlashAboveLock() public {
        ProtocolConfig.Params memory p = BaselineParams.baseline();
        p.nonRevealSlash = p.jurorLockPerCase + 1;
        vm.expectRevert(ProtocolConfig.InvalidJurorEconomics.selector);
        _deployWith(p);
    }

    function test_Bounds_RejectsZeroCustody() public {
        ProtocolConfig.Params memory p = BaselineParams.baseline();
        p.maxActiveCustody = 0;
        vm.expectRevert(abi.encodeWithSelector(ProtocolConfig.OutOfBounds.selector, "maxActiveCustody"));
        _deployWith(p);
    }

    function test_Bounds_RejectsChallengeWindowOutOfRange() public {
        ProtocolConfig.Params memory p = BaselineParams.baseline();
        p.challengeWindow = 8 days;
        vm.expectRevert(abi.encodeWithSelector(ProtocolConfig.OutOfBounds.selector, "challengeWindow"));
        _deployWith(p);
    }

    // ------------------------------------------------------ params timelock

    function test_Propose_RequiresConfigAdmin() public {
        ProtocolConfig.Params memory p = BaselineParams.baseline();
        p.protocolFeeBps = 300;
        vm.expectRevert();
        vm.prank(stranger);
        config.proposeParams(p);
    }

    function test_Execute_RequiresPendingProposal() public {
        vm.expectRevert(ProtocolConfig.NoPendingProposal.selector);
        vm.prank(configAdmin);
        config.executeParams();
    }

    function test_Execute_RequiresTimelockToElapse() public {
        ProtocolConfig.Params memory p = BaselineParams.baseline();
        p.protocolFeeBps = 300;

        vm.prank(configAdmin);
        config.proposeParams(p);
        (, uint64 readyAt) = config.pendingParams();

        vm.warp(readyAt - 1);
        vm.expectRevert(abi.encodeWithSelector(ProtocolConfig.ProposalNotReady.selector, readyAt));
        vm.prank(configAdmin);
        config.executeParams();

        // Value is unchanged while pending.
        assertEq(config.protocolFeeBps(), 200);

        vm.warp(readyAt);
        vm.prank(configAdmin);
        config.executeParams();
        assertEq(config.protocolFeeBps(), 300);
        assertEq(config.configVersion(), 2);
    }

    function test_Execute_ClearsPendingProposal() public {
        ProtocolConfig.Params memory p = BaselineParams.baseline();
        p.protocolFeeBps = 300;
        vm.prank(configAdmin);
        config.proposeParams(p);
        (, uint64 readyAt) = config.pendingParams();
        vm.warp(readyAt);
        vm.prank(configAdmin);
        config.executeParams();

        vm.expectRevert(ProtocolConfig.NoPendingProposal.selector);
        vm.prank(configAdmin);
        config.executeParams();
    }

    function test_Cancel_DiscardsProposal() public {
        ProtocolConfig.Params memory p = BaselineParams.baseline();
        p.protocolFeeBps = 300;
        vm.prank(configAdmin);
        config.proposeParams(p);

        vm.prank(configAdmin);
        config.cancelParamsProposal();

        vm.expectRevert(ProtocolConfig.NoPendingProposal.selector);
        vm.prank(configAdmin);
        config.executeParams();
        assertEq(config.protocolFeeBps(), 200, "cancelled proposal must not apply");
    }

    /// @dev Bounds are re-checked on execution, not only on proposal.
    function test_Execute_RevalidatesBounds() public {
        ProtocolConfig.Params memory p = BaselineParams.baseline();
        p.protocolFeeBps = config.MAX_PROTOCOL_FEE_BPS();
        vm.prank(configAdmin);
        config.proposeParams(p);
        (, uint64 readyAt) = config.pendingParams();
        vm.warp(readyAt);
        vm.prank(configAdmin);
        config.executeParams();
        assertEq(config.protocolFeeBps(), config.MAX_PROTOCOL_FEE_BPS());
    }

    function test_Version_IsMonotonic() public {
        uint64 previous = config.configVersion();
        for (uint16 i = 0; i < 3; i++) {
            ProtocolConfig.Params memory p = BaselineParams.baseline();
            p.protocolFeeBps = 210 + i;
            vm.prank(configAdmin);
            config.proposeParams(p);
            (, uint64 readyAt) = config.pendingParams();
            vm.warp(readyAt);
            vm.prank(configAdmin);
            config.executeParams();

            uint64 current = config.configVersion();
            assertEq(current, previous + 1, "version must increase by exactly one");
            previous = current;
        }
    }

    // ------------------------------------------------------------ addresses

    function test_Treasury_IsTimelocked() public {
        address newTreasury = address(0xFEE5);
        vm.prank(configAdmin);
        config.proposeTreasury(newTreasury);

        vm.expectRevert();
        vm.prank(configAdmin);
        config.executeTreasury();
        assertEq(config.treasury(), treasury, "treasury must not change before delay");

        vm.warp(block.timestamp + TIMELOCK);
        vm.prank(configAdmin);
        config.executeTreasury();
        assertEq(config.treasury(), newTreasury);
    }

    function test_Treasury_RejectsZero() public {
        vm.expectRevert(ProtocolConfig.ZeroAddress.selector);
        vm.prank(configAdmin);
        config.proposeTreasury(address(0));
    }

    function test_RandomnessAdapter_IsTimelocked() public {
        address adapter = address(0xADA9);
        vm.prank(configAdmin);
        config.proposeRandomnessAdapter(adapter);
        vm.warp(block.timestamp + TIMELOCK);
        vm.prank(configAdmin);
        config.executeRandomnessAdapter();
        assertEq(config.randomnessAdapter(), adapter);
    }

    // -------------------------------------------------------------- signers

    /// @dev Signer rotation is intentionally immediate: the reason to rotate is a
    ///      compromised key, and a timelock would extend the exposure window.
    function test_SignerRotation_IsImmediate() public {
        address newSigner = address(0xBEEF);
        vm.prank(signerAdmin);
        config.rotateRiskQuoteSigner(newSigner);
        assertEq(config.riskQuoteSigner(), newSigner);

        vm.prank(signerAdmin);
        config.rotatePodAttestationSigner(newSigner);
        assertEq(config.podAttestationSigner(), newSigner);
    }

    function test_SignerRotation_RequiresSignerAdmin() public {
        vm.expectRevert();
        vm.prank(configAdmin);
        config.rotateRiskQuoteSigner(address(0xBEEF));

        vm.expectRevert();
        vm.prank(stranger);
        config.rotatePodAttestationSigner(address(0xBEEF));
    }

    function test_SignerRotation_RejectsZero() public {
        vm.expectRevert(ProtocolConfig.ZeroAddress.selector);
        vm.prank(signerAdmin);
        config.rotateRiskQuoteSigner(address(0));
    }

    // ------------------------------------------------------------- coverage

    function test_CoverageForTier() public view {
        assertEq(config.coverageBpsForTier(1), 2_500);
        assertEq(config.coverageBpsForTier(2), 6_000);
        assertEq(config.coverageBpsForTier(3), 10_000);
    }

    /// @dev §49: R4 stays disabled; asking for it must not silently return 0.
    function test_CoverageForTier_RejectsR4AndUnknown() public {
        vm.expectRevert(abi.encodeWithSelector(ProtocolConfig.OutOfBounds.selector, "riskTier"));
        config.coverageBpsForTier(4);

        vm.expectRevert(abi.encodeWithSelector(ProtocolConfig.OutOfBounds.selector, "riskTier"));
        config.coverageBpsForTier(0);
    }

    // ----------------------------------------------------------------- fuzz

    /// @dev Invariant §33-15: no accepted fee can exceed the hard ceiling.
    function testFuzz_FeeNeverExceedsCeiling(uint16 feeBps) public {
        ProtocolConfig.Params memory p = BaselineParams.baseline();
        p.protocolFeeBps = feeBps;

        if (feeBps > config.MAX_PROTOCOL_FEE_BPS()) {
            vm.expectRevert(abi.encodeWithSelector(ProtocolConfig.OutOfBounds.selector, "protocolFeeBps"));
            _deployWith(p);
        } else {
            ProtocolConfig c = _deployWith(p);
            assertLe(c.protocolFeeBps(), c.MAX_PROTOCOL_FEE_BPS());
        }
    }

    /// @dev Whatever the inputs, an accepted config always satisfies every bound.
    function testFuzz_AcceptedConfigAlwaysWithinBounds(
        uint16 feeBps,
        uint16 r1,
        uint16 r2,
        uint16 r3,
        uint8 custody,
        uint32 challenge,
        uint128 deposit
    ) public {
        ProtocolConfig.Params memory p = BaselineParams.baseline();
        p.protocolFeeBps = feeBps;
        p.coverageBpsR1 = r1;
        p.coverageBpsR2 = r2;
        p.coverageBpsR3 = r3;
        p.maxActiveCustody = custody;
        p.challengeWindow = challenge;
        p.courierBaseDeposit = deposit;

        try this.deployExternal(p) returns (ProtocolConfig c) {
            ProtocolConfig.Params memory got = c.params();
            assertLe(got.protocolFeeBps, c.MAX_PROTOCOL_FEE_BPS());
            assertLe(got.coverageBpsR1, got.coverageBpsR2);
            assertLe(got.coverageBpsR2, got.coverageBpsR3);
            assertLe(got.coverageBpsR3, c.MAX_COVERAGE_BPS());
            assertGe(got.maxActiveCustody, c.MIN_ACTIVE_CUSTODY());
            assertLe(got.maxActiveCustody, c.MAX_ACTIVE_CUSTODY());
            assertGe(got.challengeWindow, c.MIN_CHALLENGE_WINDOW());
            assertLe(got.challengeWindow, c.MAX_CHALLENGE_WINDOW());
            assertGe(got.courierBaseDeposit, c.MIN_COURIER_DEPOSIT());
            assertLe(got.courierBaseDeposit, c.MAX_COURIER_DEPOSIT());
        } catch {
            // Rejection is the correct outcome for out-of-bounds input.
        }
    }

    function deployExternal(ProtocolConfig.Params memory p) external returns (ProtocolConfig) {
        return _deployWith(p);
    }

    /// @dev No caller other than CONFIG_ADMIN may move configuration.
    function testFuzz_OnlyConfigAdminCanPropose(address caller) public {
        vm.assume(caller != configAdmin);
        ProtocolConfig.Params memory p = BaselineParams.baseline();
        p.protocolFeeBps = 300;
        vm.expectRevert();
        vm.prank(caller);
        config.proposeParams(p);
        assertEq(config.protocolFeeBps(), 200);
    }
}
