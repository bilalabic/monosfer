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

    /// @dev Incremented per acceptance so two in one test never share a nonce.
    uint256 private _nonceCounter;

    function senderKey(uint256 index) internal pure returns (uint256) {
        return SENDER_KEY_BASE + index;
    }

    function senderAddress(uint256 index) internal pure returns (address) {
        return vm.addr(senderKey(index));
    }

    /// @notice A well-formed acceptance for `deliveryId`, valid for one hour.
    function buildAcceptance(uint256 deliveryId, address courier)
        internal
        returns (PickupProof.Acceptance memory acceptance)
    {
        return buildAcceptanceWithExpiry(deliveryId, courier, uint64(block.timestamp) + 1 hours);
    }

    /// @notice An acceptance with an explicit expiry, for staleness tests.
    function buildAcceptanceWithExpiry(uint256 deliveryId, address courier, uint64 expiresAt)
        internal
        returns (PickupProof.Acceptance memory acceptance)
    {
        _nonceCounter += 1;
        acceptance = PickupProof.Acceptance({
            deliveryId: deliveryId,
            courier: courier,
            action: PickupProof.PICKUP_ACTION,
            nonce: _nonceCounter,
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
