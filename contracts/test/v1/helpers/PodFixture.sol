// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProtocolConfig} from "../../../src/v1/config/ProtocolConfig.sol";
import {DeliveryHub} from "../../../src/v1/hub/DeliveryHub.sol";
import {DeliveryProof} from "../../../src/v1/proof/DeliveryProof.sol";

/**
 * @notice Builds and signs proof-of-delivery attestations for tests.
 * @dev Shared by the unit and invariant suites so both exercise the typed data a
 *      real attestation service would sign.
 *
 *      Nonces are derived from the arguments rather than drawn from a counter,
 *      for the reason recorded in PickupFixture: counter-derived values reach
 *      calldata, which made a test's measured gas depend on which other tests
 *      ran first and broke the gas gate.
 *
 *      The digest is rebuilt here from the domain separator and the struct hash
 *      instead of calling `hub.hashPodAttestation`, so that
 *      `test_HashMatchesIndependentDerivation` compares two independent
 *      derivations rather than one function with itself.
 */
abstract contract PodFixture is Test {
    uint256 internal constant POD_SIGNER_KEY = 0x9D0DE;

    function podSignerAddress() internal pure returns (address) {
        return vm.addr(POD_SIGNER_KEY);
    }

    /// @notice A well-formed OTP attestation, valid for the configured lifetime.
    function buildAttestation(ProtocolConfig config, uint256 deliveryId, address courier)
        internal
        view
        returns (DeliveryProof.Attestation memory)
    {
        return buildAttestationFull(
            deliveryId,
            courier,
            DeliveryProof.POD_OTP,
            uint64(block.timestamp),
            uint64(block.timestamp) + config.podAttestationValidity(),
            0
        );
    }

    /**
     * @notice An attestation with every field under the caller's control.
     * @param tag Distinguishes two attestations that would otherwise be
     *        identical. Callers that need the *same* nonce assign it explicitly.
     */
    function buildAttestationFull(
        uint256 deliveryId,
        address courier,
        bytes32 proofType,
        uint64 issuedAt,
        uint64 expiresAt,
        uint256 tag
    ) internal pure returns (DeliveryProof.Attestation memory attestation) {
        attestation = DeliveryProof.Attestation({
            deliveryId: deliveryId,
            courier: courier,
            proofType: proofType,
            challengeHash: keccak256(abi.encode("monosfer-test-challenge", deliveryId, tag)),
            nonce: uint256(keccak256(abi.encode("monosfer-test-pod", deliveryId, courier, proofType, expiresAt, tag))),
            issuedAt: issuedAt,
            expiresAt: expiresAt
        });
    }

    /// @notice Sign `attestation` as the configured attestation service.
    function signAttestation(DeliveryHub hub, DeliveryProof.Attestation memory attestation)
        internal
        view
        returns (bytes memory)
    {
        return signAttestationAs(hub, attestation, POD_SIGNER_KEY);
    }

    /// @notice Sign with an arbitrary key, for forged-attestation tests.
    function signAttestationAs(DeliveryHub hub, DeliveryProof.Attestation memory attestation, uint256 key)
        internal
        view
        returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, podDigest(hub, attestation));
        return abi.encodePacked(r, s, v);
    }

    /// @notice The EIP-712 digest the attestation service signs.
    function podDigest(DeliveryHub hub, DeliveryProof.Attestation memory attestation) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", hub.quoteDomainSeparator(), DeliveryProof.hash(attestation)));
    }
}
