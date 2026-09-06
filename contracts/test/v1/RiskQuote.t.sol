// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ProtocolAccessManager} from "../../src/v1/access/ProtocolAccessManager.sol";
import {ProtocolConfig} from "../../src/v1/config/ProtocolConfig.sol";
import {BaselineParams} from "../../src/v1/config/BaselineParams.sol";
import {SettlementVault} from "../../src/v1/vault/SettlementVault.sol";
import {CourierRegistry} from "../../src/v1/registry/CourierRegistry.sol";
import {DeliveryHub} from "../../src/v1/hub/DeliveryHub.sol";
import {CoverageQuote} from "../../src/v1/risk/CoverageQuote.sol";
import {RiskQuoteVerifier} from "../../src/v1/risk/RiskQuoteVerifier.sol";
import {QuoteFixture} from "./helpers/QuoteFixture.sol";

contract RiskQuoteTest is QuoteFixture {
    ProtocolAccessManager internal manager;
    ProtocolConfig internal config;
    SettlementVault internal vault;
    CourierRegistry internal registry;
    DeliveryHub internal hub;

    address internal admin = address(0xA11CE);
    address internal signerAdmin = address(0x5165);
    address internal treasury = address(0x7EA5);
    address internal customer = address(0xC057);
    address internal stranger = address(0xBAD);

    uint96 internal constant DECLARED_VALUE = 20 ether;
    uint256 internal constant FORGED_KEY = 0xBADBEEF;

    function setUp() public {
        manager = new ProtocolAccessManager(3 days, admin);
        config = new ProtocolConfig(
            manager, 2 days, BaselineParams.baseline(), treasury, quoteSignerAddress(), address(0x2)
        );
        vault = new SettlementVault(manager);
        registry = new CourierRegistry(manager, config, vault);
        hub = new DeliveryHub(manager, config, registry, vault, 1 ether);

        vm.startPrank(admin);
        manager.grantRole(manager.SIGNER_ADMIN_ROLE(), signerAdmin);
        manager.grantRole(manager.VAULT_CONTROLLER_ROLE(), address(registry));
        manager.grantRole(manager.VAULT_CONTROLLER_ROLE(), address(hub));
        manager.grantRole(manager.REGISTRY_CONTROLLER_ROLE(), address(hub));
        vm.stopPrank();
    }

    function _create(CoverageQuote.Quote memory q, bytes memory sig) internal returns (uint256) {
        vm.prank(q.customer);
        return hub.createDelivery(q, sig);
    }

    // ------------------------------------------------------------- happy path

    function test_ValidQuoteOpensDeliveryWithQuotedCoverage() public {
        CoverageQuote.Quote memory q = buildQuote(config, customer, 1, DECLARED_VALUE);
        uint256 id = _create(q, signQuote(hub, q));

        DeliveryHub.Delivery memory d = hub.deliveryOf(id);
        assertEq(d.riskTier, 1);
        // R1 is 25% of declared value (sec. 6).
        assertEq(d.requiredCollateral, DECLARED_VALUE / 4);
        assertEq(d.customer, customer);
    }

    /// @dev sec. 6: each tier's baseline coverage must come through unchanged.
    function test_EachTierUsesItsOwnCoverageBaseline() public {
        uint16[3] memory expectedBps = [uint16(2_500), 6_000, 10_000];
        for (uint8 tier = 1; tier <= 3; tier++) {
            CoverageQuote.Quote memory q = buildQuote(config, customer, tier, DECLARED_VALUE);
            uint256 id = _create(q, signQuote(hub, q));
            assertEq(
                hub.deliveryOf(id).requiredCollateral,
                (uint256(DECLARED_VALUE) * expectedBps[tier - 1]) / 10_000,
                "tier baseline mismatch"
            );
        }
    }

    // ------------------------------------------------------------- signatures

    /// @dev The whole point: an unsigned or wrongly signed quote is worthless.
    function test_ForgedSignatureRejected() public {
        CoverageQuote.Quote memory q = buildQuote(config, customer, 1, DECLARED_VALUE);
        bytes memory forged = signQuoteAs(hub, q, FORGED_KEY);

        vm.expectRevert(abi.encodeWithSelector(RiskQuoteVerifier.QuoteSignatureInvalid.selector, hub.hashQuote(q)));
        _create(q, forged);
    }

    function test_GarbageSignatureRejected() public {
        CoverageQuote.Quote memory q = buildQuote(config, customer, 1, DECLARED_VALUE);
        vm.expectRevert();
        _create(q, hex"deadbeef");
    }

    /// @dev Tampering with any signed field must invalidate the signature.
    function test_TamperedCoverageRejected() public {
        CoverageQuote.Quote memory q = buildQuote(config, customer, 1, DECLARED_VALUE);
        bytes memory sig = signQuote(hub, q);

        // 4 ether sits inside the R1 band [3.75, 7.5], so the signature check —
        // not the band check — is what must reject this.
        q.requiredCoverage = 4 ether;
        vm.expectRevert(abi.encodeWithSelector(RiskQuoteVerifier.QuoteSignatureInvalid.selector, hub.hashQuote(q)));
        _create(q, sig);
    }

    function test_TamperedTierRejected() public {
        CoverageQuote.Quote memory q = buildQuote(config, customer, 3, DECLARED_VALUE);
        bytes memory sig = signQuote(hub, q);

        q.riskTier = 1; // cheaper tier, same coverage
        vm.expectRevert();
        _create(q, sig);
    }

    /// @dev A quote is bound to one wallet; nobody else may spend it.
    function test_QuoteIssuedToAnotherCustomerRejected() public {
        CoverageQuote.Quote memory q = buildQuote(config, customer, 1, DECLARED_VALUE);
        bytes memory sig = signQuote(hub, q);

        vm.expectRevert(abi.encodeWithSelector(RiskQuoteVerifier.QuoteNotForCaller.selector, customer, stranger));
        vm.prank(stranger);
        hub.createDelivery(q, sig);
    }

    // ----------------------------------------------------------------- replay

    /// @dev Invariant sec. 33-8: a quote redeems exactly once.
    function test_QuoteCannotBeReplayed() public {
        CoverageQuote.Quote memory q = buildQuote(config, customer, 1, DECLARED_VALUE);
        bytes memory sig = signQuote(hub, q);

        _create(q, sig);
        assertTrue(hub.quoteRedeemed(hub.hashQuote(q)), "digest must be marked redeemed");

        vm.expectRevert(abi.encodeWithSelector(RiskQuoteVerifier.QuoteAlreadyRedeemed.selector, hub.hashQuote(q)));
        _create(q, sig);
    }

    /// @dev Two quotes with identical terms differ by salt, so both are usable.
    function test_DistinctSaltsAreIndependentQuotes() public {
        CoverageQuote.Quote memory a = buildQuote(config, customer, 1, DECLARED_VALUE);
        CoverageQuote.Quote memory b = buildQuote(config, customer, 1, DECLARED_VALUE);
        assertTrue(a.salt != b.salt, "fixture must vary the salt");

        _create(a, signQuote(hub, a));
        _create(b, signQuote(hub, b));
        assertEq(hub.nextDeliveryId(), 2);
    }

    // ------------------------------------------------------------ time window

    function test_ExpiredQuoteRejected() public {
        CoverageQuote.Quote memory q = buildQuote(config, customer, 1, DECLARED_VALUE);
        bytes memory sig = signQuote(hub, q);

        vm.warp(uint256(q.expiresAt) + 1);
        vm.expectRevert(abi.encodeWithSelector(RiskQuoteVerifier.QuoteExpired.selector, q.expiresAt));
        _create(q, sig);
    }

    function test_QuoteValidUpToTheLastSecond() public {
        CoverageQuote.Quote memory q = buildQuote(config, customer, 1, DECLARED_VALUE);
        bytes memory sig = signQuote(hub, q);

        vm.warp(q.expiresAt);
        _create(q, sig);
        assertEq(hub.nextDeliveryId(), 1);
    }

    /**
     * @dev The signer states the window; the chain caps it. Without this the
     *      sec. 48 five-minute rule would live only in the backend and a
     *      long-lived quote would be indistinguishable from a valid one.
     */
    function test_OverlongValidityWindowRejected() public {
        CoverageQuote.Quote memory q = buildQuote(config, customer, 1, DECLARED_VALUE);
        uint32 maximum = config.riskQuoteValidity();
        q.expiresAt = q.issuedAt + maximum + 1;
        bytes memory sig = signQuote(hub, q);

        vm.expectRevert(
            abi.encodeWithSelector(RiskQuoteVerifier.QuoteWindowTooLong.selector, uint64(maximum) + 1, maximum)
        );
        _create(q, sig);
    }

    function test_InvertedWindowRejected() public {
        CoverageQuote.Quote memory q = buildQuote(config, customer, 1, DECLARED_VALUE);
        q.expiresAt = q.issuedAt;
        bytes memory sig = signQuote(hub, q);

        vm.expectRevert(abi.encodeWithSelector(RiskQuoteVerifier.QuoteWindowInvalid.selector, q.issuedAt, q.expiresAt));
        _create(q, sig);
    }

    // --------------------------------------------------------- coverage band

    /**
     * @dev The security property that makes the signature safe to rely on: even
     *      a correctly signed quote cannot price coverage below the band, so a
     *      compromised signer cannot remove collateral.
     */
    function test_SignedButUnderpricedQuoteRejected() public {
        CoverageQuote.Quote memory q = buildQuoteWithCoverage(config, customer, 1, DECLARED_VALUE, 1 wei);
        bytes memory sig = signQuote(hub, q);

        vm.expectRevert();
        _create(q, sig);
    }

    function test_SignedButOverpricedQuoteRejected() public {
        uint96 baseline = uint96((uint256(DECLARED_VALUE) * config.coverageBpsForTier(1)) / 10_000);
        uint96 tooHigh = uint96((uint256(baseline) * config.coverageMultiplierMaxBps()) / 10_000) + 1;

        CoverageQuote.Quote memory q = buildQuoteWithCoverage(config, customer, 1, DECLARED_VALUE, tooHigh);
        bytes memory sig = signQuote(hub, q);
        vm.expectRevert();
        _create(q, sig);
    }

    /// @dev Both edges of the band must be accepted, not just the midpoint.
    function test_BandEdgesAccepted() public {
        uint256 baseline = (uint256(DECLARED_VALUE) * config.coverageBpsForTier(2)) / 10_000;
        uint96 low = uint96((baseline * config.coverageMultiplierMinBps()) / 10_000);
        uint96 high = uint96((baseline * config.coverageMultiplierMaxBps()) / 10_000);

        CoverageQuote.Quote memory a = buildQuoteWithCoverage(config, customer, 2, DECLARED_VALUE, low);
        _create(a, signQuote(hub, a));

        CoverageQuote.Quote memory b = buildQuoteWithCoverage(config, customer, 2, DECLARED_VALUE, high);
        _create(b, signQuote(hub, b));

        assertEq(hub.deliveryOf(0).requiredCollateral, low);
        assertEq(hub.deliveryOf(1).requiredCollateral, high);
    }

    function test_ZeroDeclaredValueRejected() public {
        CoverageQuote.Quote memory q = buildQuoteWithCoverage(config, customer, 1, 0, 0);
        bytes memory sig = signQuote(hub, q);
        vm.expectRevert(RiskQuoteVerifier.QuoteDeclaredValueZero.selector);
        _create(q, sig);
    }

    /// @dev sec. 49: R4 stays disabled, and tier 0 is not a tier.
    function test_DisabledTiersRejected() public {
        for (uint8 tier = 4; tier <= 5; tier++) {
            CoverageQuote.Quote memory q = buildQuoteWithCoverage(config, customer, tier, DECLARED_VALUE, 1 ether);
            bytes memory sig = signQuote(hub, q);
            vm.expectRevert(abi.encodeWithSelector(RiskQuoteVerifier.QuoteTierInvalid.selector, tier));
            _create(q, sig);
        }
        CoverageQuote.Quote memory zero = buildQuoteWithCoverage(config, customer, 0, DECLARED_VALUE, 1 ether);
        bytes memory zeroSig = signQuote(hub, zero);
        vm.expectRevert(abi.encodeWithSelector(RiskQuoteVerifier.QuoteTierInvalid.selector, uint8(0)));
        _create(zero, zeroSig);
    }

    // ------------------------------------------------------- signer rotation

    /// @dev sec. 45: rotating the signer must invalidate quotes from the old key.
    function test_SignerRotationInvalidatesOldQuotes() public {
        CoverageQuote.Quote memory q = buildQuote(config, customer, 1, DECLARED_VALUE);
        bytes memory sig = signQuote(hub, q);

        vm.prank(signerAdmin);
        config.rotateRiskQuoteSigner(address(0xFEED));

        vm.expectRevert(abi.encodeWithSelector(RiskQuoteVerifier.QuoteSignatureInvalid.selector, hub.hashQuote(q)));
        _create(q, sig);
    }

    // --------------------------------------------------------- domain binding

    /// @dev sec. 12: the domain must bind chain id and verifying contract, so a
    ///      quote cannot be replayed against another deployment.
    function test_DomainIsBoundToThisDeployment() public {
        DeliveryHub other = new DeliveryHub(manager, config, registry, vault, 1 ether);
        assertTrue(
            hub.quoteDomainSeparator() != other.quoteDomainSeparator(),
            "two deployments must not share a domain separator"
        );

        CoverageQuote.Quote memory q = buildQuote(config, customer, 1, DECLARED_VALUE);
        bytes memory sigForOther = signQuoteAs(other, q, QUOTE_SIGNER_KEY);

        vm.expectRevert(abi.encodeWithSelector(RiskQuoteVerifier.QuoteSignatureInvalid.selector, hub.hashQuote(q)));
        _create(q, sigForOther);
    }

    // ----------------------------------------------------------------- fuzz

    /// @dev Whatever the signer asks for, accepted coverage stays inside the band.
    function testFuzz_AcceptedCoverageAlwaysInsideBand(uint8 tier, uint96 declaredValue, uint96 coverage) public {
        tier = uint8(bound(tier, 1, 3));
        declaredValue = uint96(bound(declaredValue, 1 ether, 1_000 ether));

        CoverageQuote.Quote memory q = buildQuoteWithCoverage(config, customer, tier, declaredValue, coverage);
        bytes memory sig = signQuote(hub, q);

        vm.prank(customer);
        try hub.createDelivery(q, sig) returns (uint256 id) {
            uint256 baseline = (uint256(declaredValue) * config.coverageBpsForTier(tier)) / 10_000;
            uint256 low = (baseline * config.coverageMultiplierMinBps()) / 10_000;
            uint256 high = (baseline * config.coverageMultiplierMaxBps()) / 10_000;
            uint256 applied = hub.deliveryOf(id).requiredCollateral;
            assertGe(applied, low, "accepted coverage below the band");
            assertLe(applied, high, "accepted coverage above the band");
        } catch {
            // Rejection is the correct outcome outside the band.
        }
    }

    /// @dev No key other than the configured signer can open a delivery.
    function testFuzz_OnlyConfiguredSignerIsAccepted(uint256 key) public {
        key = bound(key, 1, type(uint128).max);
        vm.assume(key != QUOTE_SIGNER_KEY);

        CoverageQuote.Quote memory q = buildQuote(config, customer, 1, DECLARED_VALUE);
        bytes memory sig = signQuoteAs(hub, q, key);
        vm.expectRevert();
        _create(q, sig);
        assertEq(hub.nextDeliveryId(), 0, "no delivery may exist");
    }
}
