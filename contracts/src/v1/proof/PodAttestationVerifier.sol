// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import {ProtocolConfig} from "../config/ProtocolConfig.sol";
import {DeliveryProof} from "./DeliveryProof.sol";

/**
 * @title PodAttestationVerifier
 * @notice Validates signed proof-of-delivery attestations and burns their nonces.
 * @dev Baseline refs: sec. 15, sec. 12, sec. 48, invariant sec. 33-7.
 *
 *      ## What the checks are
 *
 *      | Check             | Enforced by                                     |
 *      |-------------------|-------------------------------------------------|
 *      | correct delivery  | `deliveryId` compared to the call's delivery    |
 *      | correct courier   | `courier` compared to the delivery's courier    |
 *      | known proof type  | `DeliveryProof.isKnownProofType`                |
 *      | real challenge    | `challengeHash` must be non-zero                |
 *      | lifetime          | window sane, unexpired, and capped by config    |
 *      | nonce uniqueness  | `podNonceUsed[signer][nonce]`                   |
 *      | correct signer    | `SignatureChecker` against the configured signer|
 *
 *      ## Why the chain caps the lifetime
 *
 *      The signer states the window, but sec. 48 sets its maximum at ten minutes
 *      and that rule has to live somewhere the signer cannot edit. Without the
 *      cap, an attestation could be issued with a year of validity and the limit
 *      would exist only in the backend — which is precisely the component the
 *      signature is meant to make unnecessary to trust that far.
 *
 *      ## Why an unknown proof type is rejected
 *
 *      Refusing values this contract does not recognise keeps a future proof
 *      type from being accepted before the code understands what it means. A
 *      new type is a deliberate change here, not something a signer can
 *      introduce unilaterally.
 *
 *      ## What a compromised signer can and cannot do
 *
 *      This key can assert delivery, so it is a real trust point — which is why
 *      it rotates independently of the risk-quote signer (`SIGNER_ADMIN_ROLE`)
 *      and the deploy script refuses to let one address hold both. What it
 *      cannot do is settle: an attestation only opens the challenge window
 *      (sec. 16), leaving the customer time to dispute before value moves.
 *
 *      Rotation invalidates outstanding attestations immediately, because nonces
 *      are scoped to the signing account and the signature is checked against
 *      whichever signer the config names at submission time.
 *
 *      Signatures are checked with `SignatureChecker`, so the attestation
 *      service can be a smart account (ERC-1271) rather than an EOA.
 *
 *      Like the pickup verifier, this contract does not supply the EIP-712
 *      constructor arguments: the protocol has one domain and the concrete
 *      contract's `RiskQuoteVerifier` base names it.
 */
abstract contract PodAttestationVerifier is EIP712 {
    using DeliveryProof for DeliveryProof.Attestation;

    /// @notice Nonces already spent, per signing account.
    mapping(address => mapping(uint256 => bool)) public podNonceUsed;

    event PodAttestationConsumed(
        uint256 indexed deliveryId,
        address indexed courier,
        bytes32 indexed proofType,
        bytes32 challengeHash,
        uint256 nonce,
        bytes32 digest
    );

    error PodProofWrongDelivery(uint256 expected, uint256 actual);
    error PodProofWrongCourier(address expected, address actual);
    error PodProofUnknownType(bytes32 proofType);
    error PodProofChallengeMissing();
    error PodProofWindowInvalid(uint64 issuedAt, uint64 expiresAt);
    error PodProofExpired(uint64 expiresAt);
    error PodProofWindowTooLong(uint64 window, uint32 maximum);
    error PodProofNonceUsed(address signer, uint256 nonce);
    error PodProofSignatureInvalid(bytes32 digest);

    /// @notice EIP-712 digest of `attestation` for this chain and this contract.
    function hashPodAttestation(DeliveryProof.Attestation calldata attestation) public view returns (bytes32) {
        return _hashTypedDataV4(attestation.hash());
    }

    /// @notice The proof-type values an attestation may carry.
    function podProofTypes() external pure returns (bytes32 otp, bytes32 qr, bytes32 recipientSignature) {
        return (DeliveryProof.POD_OTP, DeliveryProof.POD_QR, DeliveryProof.POD_RECIPIENT_SIGNATURE);
    }

    /**
     * @notice Validate an attestation, burn its nonce and return its digest.
     * @dev Burns before returning, so a reentrant caller cannot spend the same
     *      attestation twice.
     * @param config Supplies the attestation signer and the lifetime cap.
     * @param deliveryId The delivery being proven delivered.
     * @param courier The courier the chain has recorded for it.
     * @param attestation The signed attestation.
     * @param signature EOA or ERC-1271 signature over `hashPodAttestation`.
     * @return digest The consumed attestation's EIP-712 digest.
     */
    function _consumePodAttestation(
        ProtocolConfig config,
        uint256 deliveryId,
        address courier,
        DeliveryProof.Attestation calldata attestation,
        bytes calldata signature
    ) internal returns (bytes32 digest) {
        if (attestation.deliveryId != deliveryId) {
            revert PodProofWrongDelivery(deliveryId, attestation.deliveryId);
        }
        if (attestation.courier != courier) revert PodProofWrongCourier(courier, attestation.courier);
        if (!DeliveryProof.isKnownProofType(attestation.proofType)) {
            revert PodProofUnknownType(attestation.proofType);
        }
        if (attestation.challengeHash == bytes32(0)) revert PodProofChallengeMissing();

        _checkWindow(config, attestation);

        address signer = config.podAttestationSigner();
        if (podNonceUsed[signer][attestation.nonce]) revert PodProofNonceUsed(signer, attestation.nonce);

        digest = _hashTypedDataV4(attestation.hash());
        if (!SignatureChecker.isValidSignatureNow(signer, digest, signature)) {
            revert PodProofSignatureInvalid(digest);
        }

        podNonceUsed[signer][attestation.nonce] = true;
        emit PodAttestationConsumed(
            deliveryId, courier, attestation.proofType, attestation.challengeHash, attestation.nonce, digest
        );
    }

    /// @dev sec. 48 caps the lifetime at ten minutes; the chain enforces it.
    function _checkWindow(ProtocolConfig config, DeliveryProof.Attestation calldata attestation) private view {
        if (attestation.expiresAt <= attestation.issuedAt) {
            revert PodProofWindowInvalid(attestation.issuedAt, attestation.expiresAt);
        }
        if (block.timestamp > attestation.expiresAt) revert PodProofExpired(attestation.expiresAt);

        uint64 window = attestation.expiresAt - attestation.issuedAt;
        uint32 maximum = config.podAttestationValidity();
        if (window > maximum) revert PodProofWindowTooLong(window, maximum);
    }
}
