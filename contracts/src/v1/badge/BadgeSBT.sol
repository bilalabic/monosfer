// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {ProtocolAccessManager} from "../access/ProtocolAccessManager.sol";
import {CourierRegistry} from "../registry/CourierRegistry.sol";
import {ReputationRegistry} from "../reputation/ReputationRegistry.sol";
import {IERC5192} from "./IERC5192.sol";

/**
 * @title BadgeSBT
 * @notice Non-transferable achievement badges (sec. 24).
 * @dev Baseline refs: sec. 24 (badge list, ERC-721 + ERC-5192, badges never
 *      eliminate collateral), sec. 22 (ranking is not decided on chain).
 *
 *      ## Badges are claimed, never pushed
 *
 *      Nothing in the settlement path calls this contract. A courier (or anyone
 *      on their behalf) claims a badge once they have earned it, and the claim
 *      reads the reputation registry to check.
 *
 *      That is a deliberate structural choice rather than a convenience. Minting
 *      from inside `confirmDelivery` means a bug here — a revert, an out-of-gas,
 *      a duplicate check gone wrong — can strand somebody's payout. A decorative
 *      subsystem must not be able to do that, and the surest way to guarantee it
 *      is to leave settlement with no edge to this contract at all.
 *
 *      ## Two kinds of badge, and only one of them can be permissionless
 *
 *      Most badges are statements about on-chain history, so anyone can claim
 *      them and the contract verifies the claim itself. `TopTenWeekly` is not:
 *      sec. 22 puts ranking in an indexer precisely because sorting couriers on
 *      chain does not scale, so the chain cannot know who placed in the top ten.
 *      That badge is therefore awarded by `BADGE_AWARDER_ROLE`, and the split is
 *      visible in the API rather than hidden behind a claim that silently trusts
 *      an oracle.
 *
 *      ## Badges never reduce required collateral
 *
 *      sec. 24 allows verification badges to affect eligibility but forbids them
 *      from eliminating collateral. This contract holds no coverage logic and is
 *      referenced by nothing that computes it: the badge is a *view* of the
 *      registry's verification level, not an input to it. The relationship runs
 *      one way, and a test pins it.
 */
contract BadgeSBT is ERC721, IERC5192 {
    // --------------------------------------------------------------------
    // Types
    // --------------------------------------------------------------------

    /// @dev The sec. 24 list. `None` exists only to make an unset value invalid.
    enum BadgeType {
        None,
        FirstDelivery,
        TenDeliveries,
        FiftyDeliveries,
        HundredDeliveries,
        FiveHundredDeliveries,
        ZeroLostDispute,
        TopTenWeekly,
        VerifiedCourier,
        TrustedCourier
    }

    uint256 internal constant BADGE_COUNT = uint256(type(BadgeType).max) + 1;

    // --------------------------------------------------------------------
    // Storage
    // --------------------------------------------------------------------

    ProtocolAccessManager public immutable accessManager;
    ReputationRegistry public immutable reputation;
    CourierRegistry public immutable registry;

    /// @notice Metadata root. The backend serves `<baseURI><badgeType>.json`.
    string public baseURI;

    uint256 public nextTokenId;

    mapping(uint256 => BadgeType) public badgeOf;
    mapping(address => mapping(BadgeType => bool)) public holds;

    // --------------------------------------------------------------------
    // Events and errors
    // --------------------------------------------------------------------

    event BadgeMinted(address indexed courier, BadgeType indexed badgeType, uint256 indexed tokenId);
    event BaseURIUpdated(string baseURI);

    error ZeroAddress();
    error UnknownBadge();
    error AlreadyHeld(address courier, BadgeType badgeType);
    error NotEarned(address courier, BadgeType badgeType);
    error NotClaimable(BadgeType badgeType);
    error Soulbound();
    error NonexistentToken(uint256 tokenId);

    // --------------------------------------------------------------------
    // Wiring
    // --------------------------------------------------------------------

    constructor(
        ProtocolAccessManager accessManager_,
        ReputationRegistry reputation_,
        CourierRegistry registry_,
        string memory baseURI_
    ) ERC721("MONOSFER Badge", "MONBADGE") {
        if (address(accessManager_) == address(0)) revert ZeroAddress();
        if (address(reputation_) == address(0)) revert ZeroAddress();
        if (address(registry_) == address(0)) revert ZeroAddress();

        accessManager = accessManager_;
        reputation = reputation_;
        registry = registry_;
        baseURI = baseURI_;
    }

    // --------------------------------------------------------------------
    // Claiming
    // --------------------------------------------------------------------

    /**
     * @notice Mint a badge the courier has demonstrably earned.
     * @dev Permissionless: the claim is checked against on-chain history, so who
     *      submits it does not matter. A courier without a wallet habit can have
     *      someone else pay the gas, and the badge still lands on the courier.
     */
    function claim(address courier, BadgeType badgeType) external {
        if (courier == address(0)) revert ZeroAddress();
        if (badgeType == BadgeType.None) revert UnknownBadge();
        if (badgeType == BadgeType.TopTenWeekly) revert NotClaimable(badgeType);
        if (holds[courier][badgeType]) revert AlreadyHeld(courier, badgeType);
        if (!isEarned(courier, badgeType)) revert NotEarned(courier, badgeType);

        _mintBadge(courier, badgeType);
    }

    /**
     * @notice Award a badge the chain cannot verify for itself.
     * @dev Only `TopTenWeekly` (sec. 22: the ranking lives in the indexer). The
     *      role is deliberately narrow — it cannot mint the history-based badges,
     *      so a compromised awarder cannot fabricate a delivery record.
     */
    function award(address courier, BadgeType badgeType) external {
        accessManager.requireRole(accessManager.BADGE_AWARDER_ROLE(), msg.sender);
        if (courier == address(0)) revert ZeroAddress();
        if (badgeType != BadgeType.TopTenWeekly) revert NotClaimable(badgeType);
        if (holds[courier][badgeType]) revert AlreadyHeld(courier, badgeType);

        _mintBadge(courier, badgeType);
    }

    /// @notice Whether the chain can see that `courier` earned `badgeType`.
    function isEarned(address courier, BadgeType badgeType) public view returns (bool) {
        ReputationRegistry.Record memory r = reputation.recordOf(courier);

        if (badgeType == BadgeType.FirstDelivery) return r.completed >= 1;
        if (badgeType == BadgeType.TenDeliveries) return r.completed >= 10;
        if (badgeType == BadgeType.FiftyDeliveries) return r.completed >= 50;
        if (badgeType == BadgeType.HundredDeliveries) return r.completed >= 100;
        if (badgeType == BadgeType.FiveHundredDeliveries) return r.completed >= 500;

        // "Zero lost" has to mean something: a courier who has never been
        // disputed has not demonstrated anything about disputes.
        if (badgeType == BadgeType.ZeroLostDispute) return r.disputesLost == 0 && r.disputesWon > 0;

        if (badgeType == BadgeType.VerifiedCourier) {
            return registry.courierOf(courier).level >= CourierRegistry.VerificationLevel.C1;
        }
        if (badgeType == BadgeType.TrustedCourier) {
            return registry.courierOf(courier).level == CourierRegistry.VerificationLevel.C2;
        }
        return false;
    }

    /// @notice Every badge `courier` currently holds.
    function badgesOf(address courier) external view returns (BadgeType[] memory held) {
        uint256 count = 0;
        for (uint256 i = 1; i < BADGE_COUNT; i++) {
            if (holds[courier][BadgeType(i)]) count++;
        }
        held = new BadgeType[](count);
        uint256 j = 0;
        for (uint256 i = 1; i < BADGE_COUNT; i++) {
            if (holds[courier][BadgeType(i)]) held[j++] = BadgeType(i);
        }
    }

    function _mintBadge(address courier, BadgeType badgeType) internal {
        uint256 tokenId = nextTokenId++;
        holds[courier][badgeType] = true;
        badgeOf[tokenId] = badgeType;

        _safeMint(courier, tokenId);
        emit Locked(tokenId);
        emit BadgeMinted(courier, badgeType, tokenId);
    }

    // --------------------------------------------------------------------
    // Soulbound behaviour (ERC-5192)
    // --------------------------------------------------------------------

    /**
     * @dev The single chokepoint every ERC-721 movement passes through in
     *      OpenZeppelin 5.x. Minting (`from == 0`) is allowed; everything else —
     *      transfer, `safeTransferFrom`, and burning — is refused. Overriding
     *      here rather than the individual entry points means a future OZ version
     *      cannot add a path that bypasses the rule.
     */
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0)) revert Soulbound();
        return super._update(to, tokenId, auth);
    }

    /// @dev Approvals are meaningless for a token that cannot move; refuse them
    ///      outright rather than letting a wallet display a live allowance.
    function approve(address, uint256) public pure override {
        revert Soulbound();
    }

    function setApprovalForAll(address, bool) public pure override {
        revert Soulbound();
    }

    /// @inheritdoc IERC5192
    function locked(uint256 tokenId) external view returns (bool) {
        if (_ownerOf(tokenId) == address(0)) revert NonexistentToken(tokenId);
        return true;
    }

    // --------------------------------------------------------------------
    // Metadata
    // --------------------------------------------------------------------

    /// @dev One document per badge type, not per token: every FirstDelivery badge
    ///      is the same badge, and minting a thousand identical JSON files would
    ///      be a hosting bill with no reader.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (_ownerOf(tokenId) == address(0)) revert NonexistentToken(tokenId);
        return string.concat(baseURI, Strings.toString(uint256(badgeOf[tokenId])), ".json");
    }

    function setBaseURI(string calldata newBaseURI) external {
        accessManager.requireRole(accessManager.CONFIG_ADMIN_ROLE(), msg.sender);
        baseURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IERC5192).interfaceId || super.supportsInterface(interfaceId);
    }
}
