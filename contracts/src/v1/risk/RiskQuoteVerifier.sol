// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import {ProtocolConfig} from "../config/ProtocolConfig.sol";
import {CoverageQuote} from "./CoverageQuote.sol";

/**
 * @title RiskQuoteVerifier
 * @notice Validates signed coverage quotes and records their single use.
 * @dev Baseline refs: sec. 6, sec. 8.3, sec. 12, sec. 48, invariant sec. 33-8
 *      (coverage quotes cannot be replayed).
 *
 *      ## Why the chain re-derives the bounds
 *
 *      Without this contract the customer chose both the risk tier and the
 *      collateral, so an R3 delivery could be opened backed by one wei. The quote
 *      moves that decision to the risk service — but a signature alone would only
 *      move the trust, not reduce it: whoever holds the signing key could then
 *      price any delivery at zero collateral.
 *
 *      So the signature is necessary and not sufficient. Every quote is also
 *      checked against a band the chain computes itself:
 *
 *          baseline = declaredValue x tierCoverageBps / 10_000
 *          allowed  = [ baseline x minMultiplier , baseline x maxMultiplier ]
 *
 *      The risk service prices freely inside that band — that is where
 *      reputation discounts live (sec. 8.3) — and cannot leave it. A compromised
 *      signer can misprice a delivery; it cannot remove collateral.
 *
 *      ## Replay protection
 *
 *      The EIP-712 digest is the replay key. Each distinct quote redeems once,
 *      and `salt` makes two otherwise identical quotes distinct. Chain id and
 *      verifying contract live in the domain separator, so a quote cannot cross
 *      chains or deployments (sec. 12).
 *
 *      Signatures are checked with `SignatureChecker`, so a smart-account risk
 *      service (ERC-1271) works exactly like an EOA one.
 */
abstract contract RiskQuoteVerifier is EIP712 {
    using CoverageQuote for CoverageQuote.Quote;

    uint256 internal constant BPS_DENOMINATOR = 10_000;

    /// @notice Digests of quotes already redeemed.
    mapping(bytes32 => bool) public quoteRedeemed;

    event CoverageQuoteRedeemed(
        bytes32 indexed digest, address indexed customer, uint8 riskTier, uint96 declaredValue, uint96 requiredCoverage
    );

    error QuoteNotForCaller(address expected, address actual);
    error QuoteExpired(uint64 expiresAt);
    error QuoteWindowTooLong(uint64 window, uint32 maximum);
    error QuoteWindowInvalid(uint64 issuedAt, uint64 expiresAt);
    error QuoteAlreadyRedeemed(bytes32 digest);
    error QuoteSignatureInvalid(bytes32 digest);
    error QuoteTierInvalid(uint8 riskTier);
    error QuoteCoverageOutOfBand(uint96 requiredCoverage, uint256 minAllowed, uint256 maxAllowed);
    error QuoteDeclaredValueZero();

    constructor() EIP712("MONOSFER", "1") {}

    /// @notice The domain separator quotes must be signed against.
    function quoteDomainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @notice EIP-712 digest of `quote` for this chain and this contract.
    function hashQuote(CoverageQuote.Quote calldata quote) public view returns (bytes32) {
        return _hashTypedDataV4(quote.hash());
    }

    /**
     * @notice Validate a quote, mark it redeemed and return its digest.
     * @dev Reverts on the first failed check so the caller learns exactly which
     *      rule was broken. Marks the digest before returning, so a reentrant
     *      caller cannot redeem the same quote twice.
     * @param config Protocol configuration supplying the signer, the validity
     *        window, the tier coverage table and the multiplier band.
     * @param quote The signed quote.
     * @param signature EOA or ERC-1271 signature over `hashQuote(quote)`.
     * @return digest The redeemed quote's EIP-712 digest.
     */
    function _redeemQuote(ProtocolConfig config, CoverageQuote.Quote calldata quote, bytes calldata signature)
        internal
        returns (bytes32 digest)
    {
        if (quote.customer != msg.sender) revert QuoteNotForCaller(quote.customer, msg.sender);
        if (quote.declaredValue == 0) revert QuoteDeclaredValueZero();
        if (quote.riskTier == 0 || quote.riskTier > 3) revert QuoteTierInvalid(quote.riskTier);

        _checkWindow(config, quote);
        _checkCoverageBand(config, quote);

        digest = _hashTypedDataV4(quote.hash());
        if (quoteRedeemed[digest]) revert QuoteAlreadyRedeemed(digest);
        if (!SignatureChecker.isValidSignatureNow(config.riskQuoteSigner(), digest, signature)) {
            revert QuoteSignatureInvalid(digest);
        }

        quoteRedeemed[digest] = true;
        emit CoverageQuoteRedeemed(digest, quote.customer, quote.riskTier, quote.declaredValue, quote.requiredCoverage);
    }

    /**
     * @dev The signer states the window, but the chain caps how long it may be.
     *      Otherwise a quote could be issued with a year of validity and the
     *      sec. 48 five-minute rule would exist only in the backend.
     */
    function _checkWindow(ProtocolConfig config, CoverageQuote.Quote calldata quote) private view {
        if (quote.expiresAt <= quote.issuedAt) revert QuoteWindowInvalid(quote.issuedAt, quote.expiresAt);
        if (block.timestamp > quote.expiresAt) revert QuoteExpired(quote.expiresAt);

        uint64 window = quote.expiresAt - quote.issuedAt;
        uint32 maximum = config.riskQuoteValidity();
        if (window > maximum) revert QuoteWindowTooLong(window, maximum);
    }

    /**
     * @dev See the contract note: signature necessary, band sufficient.
     *
     *      Both bounds divide once, at the end. Computing the tier baseline first
     *      and then applying the multiplier would round twice and shift the band
     *      by a wei or two — small, but it would make the accepted range depend on
     *      rounding rather than on policy.
     *
     *      Overflow is not reachable: declaredValue is uint96, coverage bps is at
     *      most 10_000 and the multiplier at most 20_000, so the numerator stays
     *      far below uint256.
     */
    function _checkCoverageBand(ProtocolConfig config, CoverageQuote.Quote calldata quote) private view {
        uint256 scaled = uint256(quote.declaredValue) * config.coverageBpsForTier(quote.riskTier);
        uint256 denominator = BPS_DENOMINATOR * BPS_DENOMINATOR;

        uint256 minAllowed = (scaled * config.coverageMultiplierMinBps()) / denominator;
        uint256 maxAllowed = (scaled * config.coverageMultiplierMaxBps()) / denominator;

        if (quote.requiredCoverage < minAllowed || quote.requiredCoverage > maxAllowed) {
            revert QuoteCoverageOutOfBand(quote.requiredCoverage, minAllowed, maxAllowed);
        }
    }
}
