// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title CoverageQuote
 * @notice EIP-712 typed data for a signed coverage quote.
 * @dev Baseline refs: sec. 6 (risk tiers), sec. 8.3 (coverage and bonds),
 *      sec. 12 (typed-data binding rules), sec. 48 (quote validity window).
 *
 *      A quote is the risk service's priced answer for one delivery: which tier
 *      it falls in and how much collateral the selected courier must lock. It is
 *      produced off-chain because the inputs — declared value, route, history —
 *      are off-chain data (sec. 34), and signed so the chain can trust it without
 *      seeing them.
 *
 *      The struct binds every field that could otherwise be swapped:
 *      - `customer` so a quote issued for one wallet cannot be spent by another,
 *      - `salt` so two otherwise identical quotes are distinct,
 *      - `issuedAt`/`expiresAt` so a stale price cannot be replayed later.
 *
 *      Chain id and verifying contract are bound by the EIP-712 domain rather
 *      than by struct fields, so the same quote cannot be replayed on another
 *      chain or against another deployment.
 */
library CoverageQuote {
    /**
     * @param customer   The only address permitted to redeem this quote.
     * @param riskTier   1..3. Tier 4 is disabled (sec. 49).
     * @param declaredValue Package value the quote was priced against.
     * @param requiredCoverage Collateral the selected courier must lock.
     * @param issuedAt   When the risk service priced it.
     * @param expiresAt  Last timestamp at which it may be redeemed.
     * @param salt       Uniqueness, so repeat quotes hash differently.
     */
    struct Quote {
        address customer;
        uint8 riskTier;
        uint96 declaredValue;
        uint96 requiredCoverage;
        uint64 issuedAt;
        uint64 expiresAt;
        bytes32 salt;
    }

    /// @dev keccak256 of the type string. Field order must match `Quote` exactly.
    bytes32 internal constant TYPEHASH = keccak256(
        "Quote(address customer,uint8 riskTier,uint96 declaredValue,uint96 requiredCoverage,uint64 issuedAt,uint64 expiresAt,bytes32 salt)"
    );

    /// @notice EIP-712 `hashStruct` of a quote.
    function hash(Quote memory quote) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                TYPEHASH,
                quote.customer,
                quote.riskTier,
                quote.declaredValue,
                quote.requiredCoverage,
                quote.issuedAt,
                quote.expiresAt,
                quote.salt
            )
        );
    }
}
