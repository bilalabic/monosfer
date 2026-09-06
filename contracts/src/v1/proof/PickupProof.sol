// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title PickupProof
 * @notice EIP-712 typed data for a sender's acceptance of a physical handover.
 * @dev Baseline refs: sec. 11 (pickup transition), sec. 12 (pickup proof and its
 *      binding rules), invariant sec. 33-7 (proof nonces cannot be replayed).
 *
 *      ## What this message is
 *
 *      Taking custody moves liability onto the courier: from that moment they
 *      hold the package, their collateral answers for it, and the transit clock
 *      runs. A claim of pickup is therefore only trustworthy when both sides are
 *      present for it — the courier submits the transaction, and the sender signs
 *      this acceptance confirming they handed the package to that courier.
 *
 *      Either half alone is a unilateral assertion. A courier signing their own
 *      pickup proves nothing they could not already claim by calling the
 *      function; a sender acting alone could start the transit clock against a
 *      courier who never received anything.
 *
 *      ## What the struct binds
 *
 *      - `deliveryId` so an acceptance cannot be moved to another delivery,
 *      - `courier` so the sender attests to *which* courier took the package,
 *      - `action` so a signature collected for one step can never satisfy
 *        another; sec. 12 asks for this check explicitly rather than leaving the
 *        meaning of a signature implicit in where it is used,
 *      - `nonce` so each acceptance is single-use,
 *      - `expiresAt` so an acceptance signed and never used goes stale.
 *
 *      Chain id and verifying contract are bound by the EIP-712 domain rather
 *      than by struct fields, so an acceptance cannot be replayed on another
 *      chain or against another deployment. sec. 12 is explicit that domain
 *      separation alone is not sufficient, which is why every field above is
 *      also checked on-chain.
 */
library PickupProof {
    /**
     * @param deliveryId The delivery this acceptance is for.
     * @param courier    The courier the sender handed the package to.
     * @param action     Must equal `PICKUP_ACTION`.
     * @param nonce      Sender-scoped, single-use.
     * @param expiresAt  Last timestamp at which it may be submitted.
     */
    struct Acceptance {
        uint256 deliveryId;
        address courier;
        bytes32 action;
        uint256 nonce;
        uint64 expiresAt;
    }

    /**
     * @notice The only action value `confirmPickup` accepts.
     * @dev A named constant rather than a bare zero or an enum: future proofs
     *      (return handover, proof of delivery) get their own value, so a
     *      signature gathered for one can never be replayed into another.
     */
    bytes32 internal constant PICKUP_ACTION = keccak256("MONOSFER.PICKUP");

    /// @dev keccak256 of the type string. Field order must match `Acceptance`.
    bytes32 internal constant TYPEHASH =
        keccak256("PickupAcceptance(uint256 deliveryId,address courier,bytes32 action,uint256 nonce,uint64 expiresAt)");

    /// @notice EIP-712 `hashStruct` of an acceptance.
    function hash(Acceptance memory acceptance) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                TYPEHASH,
                acceptance.deliveryId,
                acceptance.courier,
                acceptance.action,
                acceptance.nonce,
                acceptance.expiresAt
            )
        );
    }
}
