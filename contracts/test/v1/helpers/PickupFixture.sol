// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {DeliveryHub} from "../../../src/v1/hub/DeliveryHub.sol";
import {PickupProof} from "../../../src/v1/proof/PickupProof.sol";

/**
 * @notice Builds and signs pickup acceptances for tests.
 * @dev Shared by the unit and invariant suites so both exercise the same typed
 *      data a real sender's wallet would sign. Keeping it in one place means a
 *      change to the struct breaks every suite at once rather than letting them
 *      drift apart.
 *
 *      The digest is rebuilt here from the domain separator and the struct hash
 *      instead of calling `hub.hashPickupAcceptance`. Signing with the same
 *      function the contract verifies against would be self-consistent even if
 *      the type string were wrong; deriving it independently means
 *      `test_HashMatchesIndependentDerivation` actually checks something.
 */
abstract contract PickupFixture is Test {
    /// @dev Senders need real keys because they sign; addresses alone will not do.
    uint256 internal constant SENDER_KEY_BASE = 0x5E4DE100;

    function senderKey(uint256 index) internal pure returns (uint256) {
        return SENDER_KEY_BASE + index;
    }

    function senderAddress(uint256 index) internal pure returns (address) {
        return vm.addr(senderKey(index));
    }

    /// @notice A well-formed acceptance for `deliveryId`, valid for one hour.
    function buildAcceptance(uint256 deliveryId, address courier)
        internal
        view
        returns (PickupProof.Acceptance memory acceptance)
    {
        return buildAcceptanceWithExpiry(deliveryId, courier, uint64(block.timestamp) + 1 hours, 0);
    }

    /**
     * @notice An acceptance with an explicit expiry and discriminator.
     * @dev The nonce is derived from the arguments rather than drawn from a
     *      counter. A counter makes the nonce a function of how many acceptances
     *      were built earlier, which depends on which other tests ran first; the
     *      nonce reaches calldata, so its byte pattern moved the measured gas of
     *      whole tests and made the gas snapshot depend on the test filter rather
     *      than on the code. Deriving it keeps every measurement reproducible in
     *      isolation.
     * @param tag Distinguishes two acceptances that would otherwise be identical,
     *        for example an authorised attempt and a forged one on the same
     *        delivery. Callers that need the *same* nonce assign it explicitly.
     */
    function buildAcceptanceWithExpiry(uint256 deliveryId, address courier, uint64 expiresAt, uint256 tag)
        internal
        pure
        returns (PickupProof.Acceptance memory acceptance)
    {
        acceptance = PickupProof.Acceptance({
            deliveryId: deliveryId,
            courier: courier,
            action: PickupProof.PICKUP_ACTION,
            nonce: uint256(keccak256(abi.encode("monosfer-test-pickup", deliveryId, courier, expiresAt, tag))),
            expiresAt: expiresAt
        });
    }

    /// @notice Sign `acceptance` with `key`.
    function signAcceptance(DeliveryHub hub, PickupProof.Acceptance memory acceptance, uint256 key)
        internal
        view
        returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, pickupDigest(hub, acceptance));
        return abi.encodePacked(r, s, v);
    }

    /// @notice The EIP-712 digest a sender's wallet would be asked to sign.
    function pickupDigest(DeliveryHub hub, PickupProof.Acceptance memory acceptance) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", hub.quoteDomainSeparator(), PickupProof.hash(acceptance)));
    }
}
