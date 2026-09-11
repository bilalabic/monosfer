// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

import {ProtocolAccessManager} from "../../src/v1/access/ProtocolAccessManager.sol";
import {ProtocolConfig} from "../../src/v1/config/ProtocolConfig.sol";
import {BaselineParams} from "../../src/v1/config/BaselineParams.sol";
import {SettlementVault} from "../../src/v1/vault/SettlementVault.sol";
import {CourierRegistry} from "../../src/v1/registry/CourierRegistry.sol";
import {ReputationRegistry} from "../../src/v1/reputation/ReputationRegistry.sol";
import {BadgeSBT} from "../../src/v1/badge/BadgeSBT.sol";
import {IERC5192} from "../../src/v1/badge/IERC5192.sol";

contract Receiver is IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}

/**
 * @notice Soulbound achievement badges (sec. 24).
 * @dev Two claims carry most of the weight here: that no path moves a badge, and
 *      that holding every badge in the set changes nothing about the collateral a
 *      courier must post.
 */
contract BadgeSBTTest is Test {
    ProtocolAccessManager internal manager;
    ProtocolConfig internal config;
    SettlementVault internal vault;
    CourierRegistry internal registry;
    ReputationRegistry internal reputation;
    BadgeSBT internal badge;

    address internal admin = address(0xA11CE);
    address internal configAdmin = address(0xC0F1);
    address internal awarder = address(0xA4A4);
    address internal verifier = address(0x7E71F1);
    address internal reporter = address(0x9E7);
    address internal treasury = address(0x7EA5);

    address internal courier = address(0xC0DE);
    address internal other = address(0xBEEF);

    function setUp() public {
        manager = new ProtocolAccessManager(3 days, admin);
        config = new ProtocolConfig(manager, 2 days, BaselineParams.baseline(), treasury, address(0x1), address(0x2));
        vault = new SettlementVault(manager);
        registry = new CourierRegistry(manager, config, vault);
        reputation = new ReputationRegistry(manager);
        badge = new BadgeSBT(manager, reputation, registry, "https://monosfer.test/badge/");

        vm.startPrank(admin);
        manager.grantRole(manager.REPUTATION_REPORTER_ROLE(), reporter);
        manager.grantRole(manager.BADGE_AWARDER_ROLE(), awarder);
        manager.grantRole(manager.VERIFIER_ROLE(), verifier);
        manager.grantRole(manager.CONFIG_ADMIN_ROLE(), configAdmin);
        manager.grantRole(manager.VAULT_CONTROLLER_ROLE(), address(registry));
        vm.stopPrank();
    }

    // ------------------------------------------------------------ helpers

    function _completeDeliveries(address who, uint32 n) internal {
        vm.startPrank(reporter);
        for (uint256 i = 0; i < n; i++) {
            reputation.recordAssignment(who);
            reputation.recordOutcome(who, i + 1, ReputationRegistry.Outcome.Completed, true);
        }
        vm.stopPrank();
    }

    function _stakeAndVerify(address who, CourierRegistry.VerificationLevel level) internal {
        uint256 amount = config.courierBaseDeposit() + 5 ether;
        vm.deal(who, amount);
        vm.prank(who);
        registry.depositStake{value: amount}();
        vm.prank(verifier);
        registry.setVerificationLevel(who, level);
    }

    // ------------------------------------------------------- ERC standards

    /// @dev sec. 24: wallets key off these to render the token correctly.
    function test_AnnouncesErc721AndErc5192() public view {
        assertTrue(badge.supportsInterface(type(IERC165).interfaceId), "ERC-165");
        assertTrue(badge.supportsInterface(type(IERC721).interfaceId), "ERC-721");
        assertTrue(badge.supportsInterface(type(IERC721Metadata).interfaceId), "ERC-721 metadata");
        assertTrue(badge.supportsInterface(type(IERC5192).interfaceId), "ERC-5192");
        assertEq(badge.supportsInterface(0xdeadbeef), false);
    }

    function test_MintEmitsLockedAndReportsLocked() public {
        _completeDeliveries(courier, 1);

        vm.expectEmit(false, false, false, true, address(badge));
        emit IERC5192.Locked(0);
        badge.claim(courier, BadgeSBT.BadgeType.FirstDelivery);

        assertTrue(badge.locked(0), "a badge is locked for good");
        assertEq(badge.ownerOf(0), courier);
    }

    function test_LockedRevertsForUnknownToken() public {
        vm.expectRevert(abi.encodeWithSelector(BadgeSBT.NonexistentToken.selector, uint256(7)));
        badge.locked(7);
    }

    function test_TokenUriIsPerBadgeType() public {
        _completeDeliveries(courier, 1);
        badge.claim(courier, BadgeSBT.BadgeType.FirstDelivery);
        assertEq(badge.tokenURI(0), "https://monosfer.test/badge/1.json");
    }

    function test_BaseUriIsConfigurableByConfigAdminOnly() public {
        vm.prank(other);
        vm.expectRevert();
        badge.setBaseURI("https://evil/");

        vm.prank(configAdmin);
        badge.setBaseURI("https://monosfer.test/v2/");

        _completeDeliveries(courier, 1);
        badge.claim(courier, BadgeSBT.BadgeType.FirstDelivery);
        assertEq(badge.tokenURI(0), "https://monosfer.test/v2/1.json");
    }

    // ------------------------------------------------------- soulbound

    /// @dev Every entry point that could move a token, one by one.
    function test_NoPathMovesABadge() public {
        _completeDeliveries(courier, 1);
        badge.claim(courier, BadgeSBT.BadgeType.FirstDelivery);
        Receiver receiver = new Receiver();

        vm.prank(courier);
        vm.expectRevert(BadgeSBT.Soulbound.selector);
        badge.transferFrom(courier, other, 0);

        vm.prank(courier);
        vm.expectRevert(BadgeSBT.Soulbound.selector);
        badge.safeTransferFrom(courier, other, 0);

        vm.prank(courier);
        vm.expectRevert(BadgeSBT.Soulbound.selector);
        badge.safeTransferFrom(courier, address(receiver), 0, "");

        vm.prank(courier);
        vm.expectRevert(BadgeSBT.Soulbound.selector);
        badge.approve(other, 0);

        vm.prank(courier);
        vm.expectRevert(BadgeSBT.Soulbound.selector);
        badge.setApprovalForAll(other, true);

        assertEq(badge.ownerOf(0), courier, "still where it was minted");
    }

    function testFuzz_NoTokenEverBecomesTransferable(address to) public {
        vm.assume(to != address(0) && to != courier && to.code.length == 0);
        _completeDeliveries(courier, 1);
        badge.claim(courier, BadgeSBT.BadgeType.FirstDelivery);

        vm.prank(courier);
        vm.expectRevert(BadgeSBT.Soulbound.selector);
        badge.transferFrom(courier, to, 0);

        assertTrue(badge.locked(0));
        assertEq(badge.ownerOf(0), courier);
    }

    // ------------------------------------------------------- earning rules

    function test_MilestonesUnlockInOrder() public {
        vm.expectRevert(abi.encodeWithSelector(BadgeSBT.NotEarned.selector, courier, BadgeSBT.BadgeType.FirstDelivery));
        badge.claim(courier, BadgeSBT.BadgeType.FirstDelivery);

        _completeDeliveries(courier, 1);
        badge.claim(courier, BadgeSBT.BadgeType.FirstDelivery);

        vm.expectRevert(abi.encodeWithSelector(BadgeSBT.NotEarned.selector, courier, BadgeSBT.BadgeType.TenDeliveries));
        badge.claim(courier, BadgeSBT.BadgeType.TenDeliveries);

        _completeDeliveries(courier, 9);
        badge.claim(courier, BadgeSBT.BadgeType.TenDeliveries);
        assertEq(badge.balanceOf(courier), 2);
    }

    function test_DuplicateClaimIsRejected() public {
        _completeDeliveries(courier, 1);
        badge.claim(courier, BadgeSBT.BadgeType.FirstDelivery);

        vm.expectRevert(
            abi.encodeWithSelector(BadgeSBT.AlreadyHeld.selector, courier, BadgeSBT.BadgeType.FirstDelivery)
        );
        badge.claim(courier, BadgeSBT.BadgeType.FirstDelivery);
        assertEq(badge.balanceOf(courier), 1);
    }

    /// @dev "Zero lost" only means something once a dispute has happened.
    function test_ZeroLostDisputeNeedsAnActualDispute() public {
        _completeDeliveries(courier, 5);
        vm.expectRevert(
            abi.encodeWithSelector(BadgeSBT.NotEarned.selector, courier, BadgeSBT.BadgeType.ZeroLostDispute)
        );
        badge.claim(courier, BadgeSBT.BadgeType.ZeroLostDispute);

        vm.prank(reporter);
        reputation.recordDispute(courier, true);
        badge.claim(courier, BadgeSBT.BadgeType.ZeroLostDispute);
        assertTrue(badge.holds(courier, BadgeSBT.BadgeType.ZeroLostDispute));
    }

    function test_ALostDisputeForfeitsTheBadge() public {
        _completeDeliveries(courier, 5);
        vm.startPrank(reporter);
        reputation.recordDispute(courier, true);
        reputation.recordDispute(courier, false);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(BadgeSBT.NotEarned.selector, courier, BadgeSBT.BadgeType.ZeroLostDispute)
        );
        badge.claim(courier, BadgeSBT.BadgeType.ZeroLostDispute);
    }

    function test_VerificationBadgesFollowTheRegistry() public {
        vm.expectRevert(
            abi.encodeWithSelector(BadgeSBT.NotEarned.selector, courier, BadgeSBT.BadgeType.VerifiedCourier)
        );
        badge.claim(courier, BadgeSBT.BadgeType.VerifiedCourier);

        _stakeAndVerify(courier, CourierRegistry.VerificationLevel.C1);
        badge.claim(courier, BadgeSBT.BadgeType.VerifiedCourier);

        vm.expectRevert(abi.encodeWithSelector(BadgeSBT.NotEarned.selector, courier, BadgeSBT.BadgeType.TrustedCourier));
        badge.claim(courier, BadgeSBT.BadgeType.TrustedCourier);

        vm.prank(verifier);
        registry.setVerificationLevel(courier, CourierRegistry.VerificationLevel.C2);
        badge.claim(courier, BadgeSBT.BadgeType.TrustedCourier);
    }

    // ------------------------------------------------ the sec. 22 boundary

    /**
     * @dev The chain cannot rank couriers (sec. 22), so it must not pretend to.
     *      The weekly badge is awarded, never claimed, and the split is enforced
     *      in both directions.
     */
    function test_WeeklyRankingCannotBeClaimed() public {
        _completeDeliveries(courier, 500);
        vm.expectRevert(abi.encodeWithSelector(BadgeSBT.NotClaimable.selector, BadgeSBT.BadgeType.TopTenWeekly));
        badge.claim(courier, BadgeSBT.BadgeType.TopTenWeekly);
    }

    function test_AwarderCanOnlyAwardTheWeeklyBadge() public {
        vm.prank(awarder);
        badge.award(courier, BadgeSBT.BadgeType.TopTenWeekly);
        assertTrue(badge.holds(courier, BadgeSBT.BadgeType.TopTenWeekly));

        // A compromised awarder must not be able to fabricate a delivery record.
        vm.prank(awarder);
        vm.expectRevert(abi.encodeWithSelector(BadgeSBT.NotClaimable.selector, BadgeSBT.BadgeType.HundredDeliveries));
        badge.award(courier, BadgeSBT.BadgeType.HundredDeliveries);
    }

    function test_OnlyAwarderMayAward() public {
        vm.prank(other);
        vm.expectRevert();
        badge.award(courier, BadgeSBT.BadgeType.TopTenWeekly);
    }

    // ------------------------------------------ the property sec. 24 demands

    /**
     * @dev "Badges must never eliminate required collateral." Proven where it
     *      matters: a courier holding every badge the contract can mint still has
     *      to post exactly the same coverage as one holding none.
     */
    function test_HoldingEveryBadgeChangesNoCollateral() public {
        _stakeAndVerify(other, CourierRegistry.VerificationLevel.C2);
        uint256 baselineDeposit = config.courierBaseDeposit();
        bool eligibleBefore = registry.isEligibleFor(other, 3);

        _completeDeliveries(other, 500);
        vm.startPrank(reporter);
        reputation.recordDispute(other, true);
        vm.stopPrank();

        BadgeSBT.BadgeType[8] memory claimable = [
            BadgeSBT.BadgeType.FirstDelivery,
            BadgeSBT.BadgeType.TenDeliveries,
            BadgeSBT.BadgeType.FiftyDeliveries,
            BadgeSBT.BadgeType.HundredDeliveries,
            BadgeSBT.BadgeType.FiveHundredDeliveries,
            BadgeSBT.BadgeType.ZeroLostDispute,
            BadgeSBT.BadgeType.VerifiedCourier,
            BadgeSBT.BadgeType.TrustedCourier
        ];
        for (uint256 i = 0; i < claimable.length; i++) {
            badge.claim(other, claimable[i]);
        }
        vm.prank(awarder);
        badge.award(other, BadgeSBT.BadgeType.TopTenWeekly);

        assertEq(badge.balanceOf(other), 9, "every badge in the sec. 24 list");
        assertEq(config.courierBaseDeposit(), baselineDeposit, "the base deposit is untouched");
        assertEq(registry.isEligibleFor(other, 3), eligibleBefore, "and eligibility is unchanged");
        assertEq(registry.courierOf(other).reserved, 0, "badges reserve nothing and release nothing");
    }

    function test_BadgesOfListsWhatIsHeld() public {
        _completeDeliveries(courier, 10);
        badge.claim(courier, BadgeSBT.BadgeType.FirstDelivery);
        badge.claim(courier, BadgeSBT.BadgeType.TenDeliveries);

        BadgeSBT.BadgeType[] memory held = badge.badgesOf(courier);
        assertEq(held.length, 2);
        assertEq(uint256(held[0]), uint256(BadgeSBT.BadgeType.FirstDelivery));
        assertEq(uint256(held[1]), uint256(BadgeSBT.BadgeType.TenDeliveries));
    }

    function test_UnknownBadgeRejected() public {
        vm.expectRevert(BadgeSBT.UnknownBadge.selector);
        badge.claim(courier, BadgeSBT.BadgeType.None);
    }

    function test_ZeroCourierRejected() public {
        vm.expectRevert(BadgeSBT.ZeroAddress.selector);
        badge.claim(address(0), BadgeSBT.BadgeType.FirstDelivery);
    }

    /// @dev Anyone may pay the gas; the badge still lands on the courier.
    function test_AnyoneMayClaimOnBehalfOfACourier() public {
        _completeDeliveries(courier, 1);
        vm.prank(other);
        badge.claim(courier, BadgeSBT.BadgeType.FirstDelivery);
        assertEq(badge.ownerOf(0), courier, "the claimant is not the recipient");
    }
}
