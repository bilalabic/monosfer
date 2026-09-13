// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ProtocolAccessManager} from "../../src/v1/access/ProtocolAccessManager.sol";
import {ProtocolConfig} from "../../src/v1/config/ProtocolConfig.sol";
import {BaselineParams} from "../../src/v1/config/BaselineParams.sol";
import {SettlementVault} from "../../src/v1/vault/SettlementVault.sol";
import {CourierRegistry} from "../../src/v1/registry/CourierRegistry.sol";
import {DeliveryHub} from "../../src/v1/hub/DeliveryHub.sol";
import {ReputationRegistry} from "../../src/v1/reputation/ReputationRegistry.sol";
import {Referral} from "../../src/v1/rewards/Referral.sol";
import {CoverageQuote} from "../../src/v1/risk/CoverageQuote.sol";
import {PickupProof} from "../../src/v1/proof/PickupProof.sol";
import {DeliveryProof} from "../../src/v1/proof/DeliveryProof.sol";
import {PodAttestationVerifier} from "../../src/v1/proof/PodAttestationVerifier.sol";
import {QuoteFixture} from "./helpers/QuoteFixture.sol";
import {PickupFixture} from "./helpers/PickupFixture.sol";
import {PodFixture} from "./helpers/PodFixture.sol";

/// @dev An attestation service that is a smart account (ERC-1271).
contract SmartAccountSigner {
    bytes4 private constant MAGIC = 0x1626ba7e;

    address private immutable owner;

    constructor(address owner_) {
        owner = owner_;
    }

    function isValidSignature(bytes32 digest, bytes calldata signature) external view returns (bytes4) {
        require(signature.length == 65, "bad sig");
        bytes32 r = bytes32(signature[0:32]);
        bytes32 s = bytes32(signature[32:64]);
        uint8 v = uint8(signature[64]);
        return ecrecover(digest, v, r, s) == owner ? MAGIC : bytes4(0);
    }
}

/**
 * @notice Proof of delivery: an attestation signed by the PoD service (sec. 15).
 * @dev The recipient may have no wallet, so their proof reaches the chain as a
 *      signed statement that the backend validated their challenge. The secret
 *      itself never appears on chain — only a commitment to it.
 */
contract PodAttestationTest is QuoteFixture, PickupFixture, PodFixture {
    ProtocolAccessManager internal manager;
    ProtocolConfig internal config;
    SettlementVault internal vault;
    CourierRegistry internal registry;
    DeliveryHub internal hub;
    ReputationRegistry internal reputation;
    Referral internal referral;

    address internal admin = address(0xA11CE);
    address internal signerAdmin = address(0x516E);
    address internal treasury = address(0x7EA5);

    address internal customer;
    uint256 internal constant COURIER_KEY = 0xC0DE10;
    address internal courier;
    address internal courier2 = address(0xC0DE2);

    uint96 internal constant BID_DEPOSIT = 1 ether;
    uint96 internal constant DECLARED_VALUE = 20 ether;
    uint96 internal constant ASK = 10 ether;
    uint96 internal constant RETURN_ASK = 2 ether;

    function setUp() public {
        customer = senderAddress(0);
        courier = vm.addr(COURIER_KEY);

        manager = new ProtocolAccessManager(3 days, admin);
        config = new ProtocolConfig(
            manager, 2 days, BaselineParams.baseline(), treasury, quoteSignerAddress(), podSignerAddress()
        );
        vault = new SettlementVault(manager);
        registry = new CourierRegistry(manager, config, vault);
        reputation = new ReputationRegistry(manager);
        referral = new Referral(manager);
        hub = new DeliveryHub(manager, config, registry, vault, reputation, referral, BID_DEPOSIT);

        vm.startPrank(admin);
        manager.grantRole(manager.VAULT_CONTROLLER_ROLE(), address(registry));
        manager.grantRole(manager.VAULT_CONTROLLER_ROLE(), address(hub));
        manager.grantRole(manager.REGISTRY_CONTROLLER_ROLE(), address(hub));
        manager.grantRole(manager.REPUTATION_REPORTER_ROLE(), address(hub));
        manager.grantRole(manager.REFERRAL_REPORTER_ROLE(), address(hub));
        manager.grantRole(manager.SIGNER_ADMIN_ROLE(), signerAdmin);
        vm.stopPrank();

        uint256 deposit = config.courierBaseDeposit();
        vm.deal(customer, 1_000 ether);
        vm.deal(courier, 1_000 ether);
        vm.deal(courier2, 1_000 ether);

        vm.prank(courier);
        registry.depositStake{value: deposit + 20 ether}();
        vm.prank(courier2);
        registry.depositStake{value: deposit + 20 ether}();
    }

    // ------------------------------------------------------------ helpers

    function _inTransit() internal returns (uint256 id) {
        CoverageQuote.Quote memory q = buildQuote(config, customer, 1, DECLARED_VALUE);
        bytes memory qsig = signQuote(hub, q);
        vm.prank(customer);
        id = hub.createDelivery(q, qsig);

        vm.prank(courier);
        hub.placeBid(id, ASK, RETURN_ASK, 30, uint64(block.timestamp + 1 hours));

        uint32 version = hub.bidOf(id, courier).termsVersion;
        vm.prank(customer);
        hub.selectCourier(id, courier, version);

        uint256 amount = hub.customerFundingAmount(id);
        vm.prank(customer);
        hub.fundAsCustomer{value: amount}(id);
        vm.prank(courier);
        hub.fundAsCourier(id);

        PickupProof.Acceptance memory acc = buildAcceptance(id, courier);
        bytes memory asig = signAcceptance(hub, acc, senderKey(0));
        vm.prank(courier);
        hub.confirmPickup(id, acc, asig);
    }

    /// @dev Only creates the listing, so it costs no custody and can coexist with
    ///      an in-transit delivery under the sec. 9 limit of one package at a time.
    function _createOnly() internal returns (uint256 id) {
        CoverageQuote.Quote memory q = buildQuote(config, customer, 1, DECLARED_VALUE);
        bytes memory qsig = signQuote(hub, q);
        vm.prank(customer);
        id = hub.createDelivery(q, qsig);
    }

    function _submit(uint256 id, DeliveryProof.Attestation memory a, bytes memory sig) internal {
        vm.prank(courier);
        hub.submitDeliveryProof(id, a, sig);
    }

    /**
     * @dev A fixed 65-byte blob standing in for "a signature the attestation
     *      service did not produce". Deriving one with `vm.sign` from a junk key
     *      works too, but its bytes come out of a cheatcode rather than out of
     *      the protocol, and the measured gas of a test then depends on how many
     *      of those bytes happen to be zero. A constant keeps the measurement a
     *      function of the code.
     */
    bytes internal constant NOT_THE_SERVICE = hex"1111111111111111111111111111111111111111111111111111111111111111"
        hex"2222222222222222222222222222222222222222222222222222222222222222" hex"1b";

    function _full(uint256 id, bytes32 proofType, uint64 issuedAt, uint64 expiresAt, uint256 tag)
        internal
        view
        returns (DeliveryProof.Attestation memory)
    {
        return buildAttestationFull(id, courier, proofType, issuedAt, expiresAt, tag);
    }

    // -------------------------------------------------------- happy path

    function test_ValidAttestation_OpensChallengeWindow() public {
        uint256 id = _inTransit();
        DeliveryProof.Attestation memory a = buildAttestation(config, id, courier);
        bytes memory sig = signAttestation(hub, a);

        _submit(id, a, sig);

        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.DeliveredPending));
        assertEq(hub.deliveryOf(id).stateDeadline, uint64(block.timestamp) + config.challengeWindow());
        assertEq(registry.courierOf(courier).activeCustody, 0, "custody closes on proof");
        assertTrue(hub.podNonceUsed(podSignerAddress(), a.nonce), "nonce burned");
    }

    /// @dev sec. 15: the chain records a commitment, never the secret.
    function test_ValidAttestation_EmitsChallengeCommitmentOnly() public {
        uint256 id = _inTransit();
        DeliveryProof.Attestation memory a = buildAttestation(config, id, courier);
        bytes memory sig = signAttestation(hub, a);

        vm.expectEmit(true, true, true, true, address(hub));
        emit PodAttestationVerifier.PodAttestationConsumed(
            id, courier, a.proofType, a.challengeHash, a.nonce, podDigest(hub, a)
        );
        _submit(id, a, sig);
    }

    /// @dev All three proof types are accepted; none is privileged over another.
    function test_EveryKnownProofTypeIsAccepted() public {
        bytes32[3] memory types = [DeliveryProof.POD_OTP, DeliveryProof.POD_QR, DeliveryProof.POD_RECIPIENT_SIGNATURE];
        for (uint256 i = 0; i < types.length; i++) {
            uint256 id = _inTransit();
            DeliveryProof.Attestation memory a =
                _full(id, types[i], uint64(block.timestamp), uint64(block.timestamp) + 5 minutes, i);
            bytes memory sig = signAttestation(hub, a);
            _submit(id, a, sig);
            assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.DeliveredPending));
        }
    }

    // --------------------------------------------------------- rejections

    /// @dev The second delivery only has to exist. sec. 9 caps a courier at one
    ///      package, so it stays a listing rather than going in transit.
    function test_Rejects_WrongDelivery() public {
        uint256 idA = _inTransit();
        uint256 idB = _createOnly();
        DeliveryProof.Attestation memory a = buildAttestation(config, idB, courier);

        bytes memory sig = signAttestation(hub, a);
        vm.expectRevert(abi.encodeWithSelector(PodAttestationVerifier.PodProofWrongDelivery.selector, idA, idB));
        _submit(idA, a, sig);
    }

    function test_Rejects_WrongCourier() public {
        uint256 id = _inTransit();
        DeliveryProof.Attestation memory a = buildAttestationFull(
            id, courier2, DeliveryProof.POD_OTP, uint64(block.timestamp), uint64(block.timestamp) + 5 minutes, 0
        );

        bytes memory sig = signAttestation(hub, a);
        vm.expectRevert(abi.encodeWithSelector(PodAttestationVerifier.PodProofWrongCourier.selector, courier, courier2));
        _submit(id, a, sig);
    }

    /// @dev A type the contract does not recognise cannot be introduced by a signer.
    function test_Rejects_UnknownProofType() public {
        uint256 id = _inTransit();
        bytes32 invented = keccak256("MONOSFER.POD.SOMETHING_NEW");
        DeliveryProof.Attestation memory a =
            _full(id, invented, uint64(block.timestamp), uint64(block.timestamp) + 5 minutes, 0);

        bytes memory sig = signAttestation(hub, a);
        vm.expectRevert(abi.encodeWithSelector(PodAttestationVerifier.PodProofUnknownType.selector, invented));
        _submit(id, a, sig);
    }

    /// @dev An attestation with no challenge behind it is not evidence of anything.
    function test_Rejects_EmptyChallengeHash() public {
        uint256 id = _inTransit();
        DeliveryProof.Attestation memory a = buildAttestation(config, id, courier);
        a.challengeHash = bytes32(0);

        bytes memory sig = signAttestation(hub, a);
        vm.expectRevert(PodAttestationVerifier.PodProofChallengeMissing.selector);
        _submit(id, a, sig);
    }

    function test_Rejects_Expired() public {
        uint256 id = _inTransit();
        uint64 issuedAt = uint64(block.timestamp);
        uint64 expiresAt = issuedAt + 5 minutes;
        DeliveryProof.Attestation memory a = _full(id, DeliveryProof.POD_OTP, issuedAt, expiresAt, 0);
        bytes memory sig = signAttestation(hub, a);

        vm.warp(expiresAt + 1);
        vm.expectRevert(abi.encodeWithSelector(PodAttestationVerifier.PodProofExpired.selector, expiresAt));
        _submit(id, a, sig);
    }

    function test_Accepts_OnFinalSecondOfValidity() public {
        uint256 id = _inTransit();
        uint64 issuedAt = uint64(block.timestamp);
        uint64 expiresAt = issuedAt + 5 minutes;
        DeliveryProof.Attestation memory a = _full(id, DeliveryProof.POD_OTP, issuedAt, expiresAt, 0);
        bytes memory sig = signAttestation(hub, a);

        vm.warp(expiresAt);
        _submit(id, a, sig);
        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.DeliveredPending));
    }

    /// @dev sec. 48 caps the lifetime at ten minutes, on chain and not in the backend.
    function test_Rejects_LifetimeBeyondBaselineCap() public {
        uint256 id = _inTransit();
        uint64 issuedAt = uint64(block.timestamp);
        uint32 cap = config.podAttestationValidity();
        uint64 expiresAt = issuedAt + cap + 1;
        DeliveryProof.Attestation memory a = _full(id, DeliveryProof.POD_OTP, issuedAt, expiresAt, 0);

        bytes memory sig = signAttestation(hub, a);
        vm.expectRevert(
            abi.encodeWithSelector(PodAttestationVerifier.PodProofWindowTooLong.selector, uint64(cap) + 1, cap)
        );
        _submit(id, a, sig);
    }

    function test_Accepts_LifetimeExactlyAtCap() public {
        uint256 id = _inTransit();
        uint32 cap = config.podAttestationValidity();
        DeliveryProof.Attestation memory a =
            _full(id, DeliveryProof.POD_OTP, uint64(block.timestamp), uint64(block.timestamp) + cap, 0);

        bytes memory sig = signAttestation(hub, a);
        _submit(id, a, sig);
        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.DeliveredPending));
    }

    function test_Rejects_InvertedWindow() public {
        uint256 id = _inTransit();
        uint64 issuedAt = uint64(block.timestamp) + 100;
        uint64 expiresAt = uint64(block.timestamp);
        DeliveryProof.Attestation memory a = _full(id, DeliveryProof.POD_OTP, issuedAt, expiresAt, 0);

        bytes memory sig = signAttestation(hub, a);
        vm.expectRevert(
            abi.encodeWithSelector(PodAttestationVerifier.PodProofWindowInvalid.selector, issuedAt, expiresAt)
        );
        _submit(id, a, sig);
    }

    function test_Rejects_ForgedSignature() public {
        uint256 id = _inTransit();
        DeliveryProof.Attestation memory a = buildAttestation(config, id, courier);
        bytes32 digest = podDigest(hub, a);

        vm.expectRevert(abi.encodeWithSelector(PodAttestationVerifier.PodProofSignatureInvalid.selector, digest));
        _submit(id, a, NOT_THE_SERVICE);
    }

    /// @dev The risk-quote key is a different trust point and cannot stand in.
    function test_Rejects_SignatureFromTheQuoteSigner() public {
        uint256 id = _inTransit();
        DeliveryProof.Attestation memory a = buildAttestation(config, id, courier);
        bytes memory sig = signAttestationAs(hub, a, QUOTE_SIGNER_KEY);

        vm.expectRevert();
        _submit(id, a, sig);
    }

    /// @dev A courier cannot attest to their own delivery.
    function test_Rejects_CourierSelfSignedAttestation() public {
        uint256 id = _inTransit();
        DeliveryProof.Attestation memory a = buildAttestation(config, id, courier);
        bytes memory sig = signAttestationAs(hub, a, COURIER_KEY);

        vm.expectRevert();
        _submit(id, a, sig);
    }

    function test_Rejects_SubmissionByNonCourier() public {
        uint256 id = _inTransit();
        DeliveryProof.Attestation memory a = buildAttestation(config, id, courier);
        bytes memory sig = signAttestation(hub, a);

        vm.expectRevert(abi.encodeWithSelector(DeliveryHub.NotCourier.selector, courier2));
        vm.prank(courier2);
        hub.submitDeliveryProof(id, a, sig);
    }

    // ------------------------------------------------------------- replay

    /// @dev Invariant sec. 33-7.
    function test_Rejects_ReusedNonce() public {
        uint256 idA = _inTransit();
        DeliveryProof.Attestation memory a = buildAttestation(config, idA, courier);
        bytes memory sig = signAttestation(hub, a);
        _submit(idA, a, sig);

        // The proof closed custody, so the courier may carry the next package.
        uint256 idB = _inTransit();
        DeliveryProof.Attestation memory b = buildAttestation(config, idB, courier);
        b.nonce = a.nonce;

        bytes memory sigB = signAttestation(hub, b);
        vm.expectRevert(
            abi.encodeWithSelector(PodAttestationVerifier.PodProofNonceUsed.selector, podSignerAddress(), a.nonce)
        );
        _submit(idB, b, sigB);
    }

    /// @dev sec. 47: an attestation captured on one delivery is worthless elsewhere.
    function test_Rejects_ReplayAcrossDeliveries() public {
        uint256 idA = _inTransit();
        DeliveryProof.Attestation memory a = buildAttestation(config, idA, courier);
        bytes memory sig = signAttestation(hub, a);
        _submit(idA, a, sig);

        uint256 idB = _inTransit();
        vm.expectRevert(abi.encodeWithSelector(PodAttestationVerifier.PodProofWrongDelivery.selector, idB, idA));
        _submit(idB, a, sig);
    }

    /// @dev A rejected attestation must leave the delivery and the nonce untouched.
    function test_FailedAttestation_ChangesNothing() public {
        uint256 id = _inTransit();
        DeliveryProof.Attestation memory a = buildAttestation(config, id, courier);

        vm.expectRevert();
        _submit(id, a, NOT_THE_SERVICE);

        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.InTransit));
        assertFalse(hub.podNonceUsed(podSignerAddress(), a.nonce));
        assertEq(registry.courierOf(courier).activeCustody, 1, "custody still open");
    }

    // ---------------------------------------------------------- rotation

    /// @dev Rotation invalidates outstanding attestations immediately.
    function test_SignerRotation_InvalidatesOutstandingAttestations() public {
        uint256 id = _inTransit();
        DeliveryProof.Attestation memory a = buildAttestation(config, id, courier);
        bytes memory sig = signAttestation(hub, a);

        address replacement = address(0xBEEF01);
        vm.prank(signerAdmin);
        config.rotatePodAttestationSigner(replacement);

        vm.expectRevert();
        _submit(id, a, sig);
    }

    // ------------------------------------------------------------- ERC-1271

    /// @dev The attestation service may be a smart account (sec. 12).
    function test_SmartAccountSigner_Accepted() public {
        SmartAccountSigner account = new SmartAccountSigner(podSignerAddress());
        vm.prank(signerAdmin);
        config.rotatePodAttestationSigner(address(account));

        uint256 id = _inTransit();
        DeliveryProof.Attestation memory a = buildAttestation(config, id, courier);

        bytes memory sig = signAttestation(hub, a);
        _submit(id, a, sig);

        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.DeliveredPending));
        assertTrue(hub.podNonceUsed(address(account), a.nonce), "nonce burned against the account");
    }

    // ------------------------------------------------------- typed data

    function test_HashMatchesIndependentDerivation() public {
        uint256 id = _inTransit();
        DeliveryProof.Attestation memory a = buildAttestation(config, id, courier);
        assertEq(hub.hashPodAttestation(a), podDigest(hub, a));
    }

    /// @dev Pickup and PoD are different statements and cannot substitute.
    function test_PickupAndPodDigestsAreDistinct() public {
        uint256 id = _inTransit();
        DeliveryProof.Attestation memory pod = buildAttestation(config, id, courier);
        PickupProof.Acceptance memory pickup = buildAcceptance(id, courier);
        assertTrue(hub.hashPodAttestation(pod) != hub.hashPickupAcceptance(pickup));
    }

    function test_ProofTypesArePublished() public view {
        (bytes32 otp, bytes32 qr, bytes32 rec) = hub.podProofTypes();
        assertEq(otp, keccak256("MONOSFER.POD.OTP"));
        assertEq(qr, keccak256("MONOSFER.POD.QR"));
        assertEq(rec, keccak256("MONOSFER.POD.RECIPIENT_SIGNATURE"));
    }

    // ----------------------------------------------------------------- fuzz

    function testFuzz_RandomSignatureNeverAccepted(bytes calldata blob) public {
        vm.assume(blob.length <= 200);
        uint256 id = _inTransit();
        DeliveryProof.Attestation memory a = buildAttestation(config, id, courier);

        vm.prank(courier);
        try hub.submitDeliveryProof(id, a, blob) {
            fail();
        } catch {}

        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.InTransit));
    }

    function testFuzz_OnlyConfiguredSignerIsAccepted(uint256 key) public {
        key = bound(key, 1, type(uint128).max);
        vm.assume(vm.addr(key) != podSignerAddress());

        uint256 id = _inTransit();
        DeliveryProof.Attestation memory a = buildAttestation(config, id, courier);

        bytes memory sig = signAttestationAs(hub, a, key);
        vm.prank(courier);
        try hub.submitDeliveryProof(id, a, sig) {
            fail();
        } catch {}
    }

    /// @dev No lifetime beyond the sec. 48 cap is ever accepted.
    function testFuzz_LifetimeCapHolds(uint64 window) public {
        window = uint64(bound(window, 1, 400 days));
        uint32 cap = config.podAttestationValidity();

        uint256 id = _inTransit();
        DeliveryProof.Attestation memory a =
            _full(id, DeliveryProof.POD_OTP, uint64(block.timestamp), uint64(block.timestamp) + window, 0);

        bytes memory sig = signAttestation(hub, a);
        vm.prank(courier);
        try hub.submitDeliveryProof(id, a, sig) {
            assertLe(window, cap, "an over-long attestation was accepted");
        } catch {}
    }
}
