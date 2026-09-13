// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProtocolConfig} from "../../../src/v1/config/ProtocolConfig.sol";
import {CoverageQuote} from "../../../src/v1/risk/CoverageQuote.sol";
import {DeliveryHub} from "../../../src/v1/hub/DeliveryHub.sol";

/**
 * @notice Builds and signs coverage quotes for tests.
 * @dev Shared by the unit and invariant suites so both exercise the same quote
 *      construction the production signer would use. Keeping it in one place
 *      means a change to the typed data breaks every suite at once rather than
 *      silently diverging.
 */
abstract contract QuoteFixture is Test {
    uint256 internal constant QUOTE_SIGNER_KEY = 0xA11CE5;

    /// @dev Incremented per quote so two quotes in one test never collide.
    /// @dev Counter-derived values that reach calldata can make a test's measured
    ///      gas depend on how many were built before it, and so on which other
    ///      tests ran — see the note in PickupFixture, where exactly that broke
    ///      the gas gate. Every snapshot entry is currently context-independent,
    ///      but prefer deriving from arguments if this fixture grows.
    uint256 private _saltCounter;

    function quoteSignerAddress() internal pure returns (address) {
        return vm.addr(QUOTE_SIGNER_KEY);
    }

    /// @notice A quote priced exactly at the tier baseline (multiplier 1.0x).
    function buildQuote(ProtocolConfig config, address customer, uint8 riskTier, uint96 declaredValue)
        internal
        returns (CoverageQuote.Quote memory quote)
    {
        uint96 coverage = uint96((uint256(declaredValue) * config.coverageBpsForTier(riskTier)) / 10_000);
        return buildQuoteWithCoverage(config, customer, riskTier, declaredValue, coverage);
    }

    /// @notice A quote with an explicit coverage figure, for band-boundary tests.
    function buildQuoteWithCoverage(
        ProtocolConfig config,
        address customer,
        uint8 riskTier,
        uint96 declaredValue,
        uint96 coverage
    ) internal returns (CoverageQuote.Quote memory quote) {
        _saltCounter += 1;
        quote = CoverageQuote.Quote({
            customer: customer,
            riskTier: riskTier,
            declaredValue: declaredValue,
            requiredCoverage: coverage,
            issuedAt: uint64(block.timestamp),
            expiresAt: uint64(block.timestamp) + config.riskQuoteValidity(),
            salt: keccak256(abi.encode("monosfer-test-quote", _saltCounter))
        });
    }

    /// @notice Sign `quote` as the configured risk service.
    function signQuote(DeliveryHub hub, CoverageQuote.Quote memory quote) internal view returns (bytes memory) {
        return signQuoteAs(hub, quote, QUOTE_SIGNER_KEY);
    }

    /// @notice Sign `quote` with an arbitrary key, for forged-signature tests.
    function signQuoteAs(DeliveryHub hub, CoverageQuote.Quote memory quote, uint256 key)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = _digest(hub, quote);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function _digest(DeliveryHub hub, CoverageQuote.Quote memory quote) private view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", hub.quoteDomainSeparator(), CoverageQuote.hash(quote)));
    }
}
