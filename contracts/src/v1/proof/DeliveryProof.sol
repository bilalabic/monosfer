// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title DeliveryProof
 * @notice EIP-712 typed data for a proof-of-delivery attestation.
 * @dev Baseline refs: sec. 15 (walletless recipient flow), sec. 12 (typed-data
 *      binding rules), sec. 48 (10-minute attestation lifetime), invariant
 *      sec. 33-7 (proof nonces cannot be replayed).
 *
 *      ## Why an attestation rather than a signature from the recipient
 *
 *      The recipient is the one person in a delivery who cannot be assumed to
 *      have a wallet. sec. 15 therefore routes their proof through the protocol
 *      instead of through a key they may not own: the recipient answers a
 *      challenge (an OTP or a scanned code), the backend checks it, and the PoD
 *      attestation service signs a typed statement that the check passed.
 *
 *      The chain never sees the secret. `challengeHash` is a commitment to it,
 *      so a dispute can later be shown which challenge was answered without the
 *      plaintext ever being published.
 *
 *      ## What the struct binds
 *
 *      - `deliveryId` so an attestation cannot be moved to another delivery,
 *      - `courier` so it names who was holding the package,
 *      - `proofType` so an OTP result is not silently read as a scanned code, or
 *        as a recipient's own signature,
 *      - `challengeHash` so the attestation is tied to one specific challenge,
 *      - `nonce` so each attestation is single-use,
 *      - `issuedAt`/`expiresAt` so the chain can cap the lifetime rather than
 *        trusting whatever window the signer states.
 *
 *      Chain id and verifying contract are bound by the EIP-712 domain, so an
 *      attestation cannot cross chains or deployments.
 */
library DeliveryProof {
    /**
     * @param deliveryId    The delivery being proven delivered.
     * @param courier       The courier who held the package.
     * @param proofType     One of the `POD_*` constants below.
     * @param challengeHash Commitment to the answered challenge. Never the secret.
     * @param nonce         Signer-scoped, single-use.
     * @param issuedAt      When the attestation service signed it.
     * @param expiresAt     Last timestamp at which it may be submitted.
     */
    struct Attestation {
        uint256 deliveryId;
        address courier;
        bytes32 proofType;
        bytes32 challengeHash;
        uint256 nonce;
        uint64 issuedAt;
        uint64 expiresAt;
    }

    /// @notice Recipient read back a one-time code (sec. 15).
    bytes32 internal constant POD_OTP = keccak256("MONOSFER.POD.OTP");

    /// @notice Courier scanned a code the recipient presented (sec. 15).
    bytes32 internal constant POD_QR = keccak256("MONOSFER.POD.QR");

    /**
     * @notice The recipient does have a wallet and signed for the package.
     * @dev Reserved and accepted as a proof type today; the contract cannot yet
     *      verify such a signature itself because a delivery carries no recipient
     *      address. Until it does, an attestation of this type still means the
     *      attestation service checked the recipient's signature off-chain.
     */
    bytes32 internal constant POD_RECIPIENT_SIGNATURE = keccak256("MONOSFER.POD.RECIPIENT_SIGNATURE");

    /// @dev keccak256 of the type string. Field order must match `Attestation`.
    bytes32 internal constant TYPEHASH = keccak256(
        "PodAttestation(uint256 deliveryId,address courier,bytes32 proofType,bytes32 challengeHash,uint256 nonce,uint64 issuedAt,uint64 expiresAt)"
    );

    /// @notice Whether `proofType` is one this contract recognises.
    function isKnownProofType(bytes32 proofType) internal pure returns (bool) {
        return proofType == POD_OTP || proofType == POD_QR || proofType == POD_RECIPIENT_SIGNATURE;
    }

    /// @notice EIP-712 `hashStruct` of an attestation.
    function hash(Attestation memory attestation) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                TYPEHASH,
                attestation.deliveryId,
                attestation.courier,
                attestation.proofType,
                attestation.challengeHash,
                attestation.nonce,
                attestation.issuedAt,
                attestation.expiresAt
            )
        );
    }
}
