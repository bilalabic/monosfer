// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import {PickupProof} from "./PickupProof.sol";

/**
 * @title PickupProofVerifier
 * @notice Validates sender-signed pickup acceptances and burns their nonces.
 * @dev Baseline refs: sec. 11, sec. 12, invariant sec. 33-7.
 *
 *      ## The six checks
 *
 *      sec. 12 states that EIP-712 domain separation alone is not sufficient and
 *      lists what the contract must enforce on top of it. Each is a separate
 *      revert here so a caller learns exactly which rule they broke:
 *
 *      | Check           | Enforced by                                    |
 *      |-----------------|------------------------------------------------|
 *      | correct delivery| `deliveryId` compared to the call's delivery   |
 *      | correct action  | `action` compared to `PICKUP_ACTION`           |
 *      | correct courier | `courier` compared to the selected courier     |
 *      | expiry          | `expiresAt` compared to `block.timestamp`      |
 *      | nonce uniqueness| `pickupNonceUsed[signer][nonce]`               |
 *      | correct signer  | `SignatureChecker` against the expected signer |
 *
 *      ## Why the nonce is scoped to the signer, not to the digest
 *
 *      Consuming the digest would already stop the identical message being
 *      submitted twice. Burning `(signer, nonce)` is strictly stronger: that
 *      nonce is spent for that signer across every delivery, action and expiry,
 *      so no variation of a signed acceptance can come back. It also matches how
 *      sec. 12 words the requirement — nonce uniqueness, not message uniqueness.
 *
 *      A nonce is burned only on a successful submission, so an acceptance that
 *      expires unused leaves its nonce free to be signed again.
 *
 *      ## Why there is no cap on the acceptance lifetime
 *
 *      Unlike a coverage quote, an acceptance does not need its own maximum
 *      window: the delivery it names is already sitting on `pickupWindow`, and
 *      once that deadline passes `poke` moves the delivery out of
 *      `ReadyForPickup` and no acceptance is redeemable at all. The state
 *      machine bounds the lifetime, so a second bound here would only be a
 *      second place to get it wrong.
 *
 *      Signatures are checked with `SignatureChecker`, so a smart-account sender
 *      (ERC-1271) works exactly like an EOA one.
 *
 *      This contract deliberately does not supply the EIP-712 constructor
 *      arguments. The protocol has one domain, and the concrete contract's other
 *      base — `RiskQuoteVerifier` — names it; a second set of arguments here
 *      would not compile, and a second domain would be wrong.
 */
abstract contract PickupProofVerifier is EIP712 {
    using PickupProof for PickupProof.Acceptance;

    /// @notice Nonces already spent, per signing account.
    mapping(address => mapping(uint256 => bool)) public pickupNonceUsed;

    event PickupAcceptanceConsumed(
        uint256 indexed deliveryId, address indexed signer, address indexed courier, uint256 nonce, bytes32 digest
    );

    error PickupProofWrongDelivery(uint256 expected, uint256 actual);
    error PickupProofWrongAction(bytes32 expected, bytes32 actual);
    error PickupProofWrongCourier(address expected, address actual);
    error PickupProofExpired(uint64 expiresAt);
    error PickupProofNonceUsed(address signer, uint256 nonce);
    error PickupProofSignatureInvalid(bytes32 digest);

    /// @notice EIP-712 digest of `acceptance` for this chain and this contract.
    function hashPickupAcceptance(PickupProof.Acceptance calldata acceptance) public view returns (bytes32) {
        return _hashTypedDataV4(acceptance.hash());
    }

    /// @notice The action value a pickup acceptance must carry.
    function pickupAction() external pure returns (bytes32) {
        return PickupProof.PICKUP_ACTION;
    }

    /// @notice The action value a return acceptance must carry (sec. 17).
    function returnAction() external pure returns (bytes32) {
        return PickupProof.RETURN_ACTION;
    }

    /**
     * @notice Validate an acceptance, burn its nonce and return its digest.
     * @dev Burns before returning, so a reentrant caller cannot spend the same
     *      acceptance twice.
     * @param deliveryId The delivery being picked up.
     * @param courier The courier the chain has selected for it.
     * @param signer The account whose signature authorises the handover.
     * @param acceptance The signed acceptance.
     * @param signature EOA or ERC-1271 signature over `hashPickupAcceptance`.
     * @return digest The consumed acceptance's EIP-712 digest.
     */
    function _consumePickupAcceptance(
        uint256 deliveryId,
        address courier,
        address signer,
        PickupProof.Acceptance calldata acceptance,
        bytes calldata signature
    ) internal returns (bytes32 digest) {
        return _consumeAcceptance(deliveryId, courier, signer, PickupProof.PICKUP_ACTION, acceptance, signature);
    }

    /**
     * @notice Validate an acceptance for a named action and burn its nonce.
     * @dev The action is a parameter rather than a constant so the outbound
     *      handover and the return each bind their own, and neither signature can
     *      stand in for the other.
     */
    function _consumeAcceptance(
        uint256 deliveryId,
        address courier,
        address signer,
        bytes32 expectedAction,
        PickupProof.Acceptance calldata acceptance,
        bytes calldata signature
    ) internal returns (bytes32 digest) {
        if (acceptance.deliveryId != deliveryId) {
            revert PickupProofWrongDelivery(deliveryId, acceptance.deliveryId);
        }
        if (acceptance.action != expectedAction) {
            revert PickupProofWrongAction(expectedAction, acceptance.action);
        }
        if (acceptance.courier != courier) revert PickupProofWrongCourier(courier, acceptance.courier);
        if (block.timestamp > acceptance.expiresAt) revert PickupProofExpired(acceptance.expiresAt);
        if (pickupNonceUsed[signer][acceptance.nonce]) revert PickupProofNonceUsed(signer, acceptance.nonce);

        digest = _hashTypedDataV4(acceptance.hash());
        if (!SignatureChecker.isValidSignatureNow(signer, digest, signature)) {
            revert PickupProofSignatureInvalid(digest);
        }

        pickupNonceUsed[signer][acceptance.nonce] = true;
        emit PickupAcceptanceConsumed(deliveryId, signer, courier, acceptance.nonce, digest);
    }
}
