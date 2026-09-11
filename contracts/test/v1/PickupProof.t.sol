// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ProtocolAccessManager} from "../../src/v1/access/ProtocolAccessManager.sol";
import {ProtocolConfig} from "../../src/v1/config/ProtocolConfig.sol";
import {BaselineParams} from "../../src/v1/config/BaselineParams.sol";
import {SettlementVault} from "../../src/v1/vault/SettlementVault.sol";
import {CourierRegistry} from "../../src/v1/registry/CourierRegistry.sol";
import {DeliveryHub} from "../../src/v1/hub/DeliveryHub.sol";
import {ReputationRegistry} from "../../src/v1/reputation/ReputationRegistry.sol";
import {CoverageQuote} from "../../src/v1/risk/CoverageQuote.sol";
import {PickupProof} from "../../src/v1/proof/PickupProof.sol";
import {PickupProofVerifier} from "../../src/v1/proof/PickupProofVerifier.sol";
import {QuoteFixture} from "./helpers/QuoteFixture.sol";
import {PickupFixture} from "./helpers/PickupFixture.sol";

/// @dev A sender that is a smart account, to prove ERC-1271 signers work (sec. 12).
contract SmartAccountSender {
    bytes4 private constant MAGIC = 0x1626ba7e;

    address private immutable owner;

    constructor(address owner_) {
        owner = owner_;
    }

    function isValidSignature(bytes32 digest, bytes calldata signature) external view returns (bytes4) {
        (uint8 v, bytes32 r, bytes32 s) = _split(signature);
        return ecrecover(digest, v, r, s) == owner ? MAGIC : bytes4(0);
    }

    function _split(bytes calldata sig) private pure returns (uint8 v, bytes32 r, bytes32 s) {
        require(sig.length == 65, "bad sig");
        r = bytes32(sig[0:32]);
        s = bytes32(sig[32:64]);
        v = uint8(sig[64]);
    }

    receive() external payable {}
}

/**
 * @notice Pickup proof: the sender's EIP-712 acceptance of a physical handover.
 * @dev Baseline refs: sec. 11, sec. 12, invariant sec. 33-7.
 *
 *      sec. 12 lists six things the contract must enforce beyond domain
 *      separation. Each has a test that breaks exactly that one rule and leaves
 *      the other five intact, so a passing suite means each check carries its
 *      own weight rather than being masked by a neighbour.
 */
contract PickupProofTest is QuoteFixture, PickupFixture {
    ProtocolAccessManager internal manager;
    ProtocolConfig internal config;
    SettlementVault internal vault;
    CourierRegistry internal registry;
    DeliveryHub internal hub;
    ReputationRegistry internal reputation;

    address internal admin = address(0xA11CE);
    address internal treasury = address(0x7EA5);

    address internal customer;
    /// @dev Key-derived so `test_Rejects_CourierSelfSignedAcceptance` can really
    ///      sign as the courier rather than merely as some other account.
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
            manager, 2 days, BaselineParams.baseline(), treasury, quoteSignerAddress(), address(0x2)
        );
        vault = new SettlementVault(manager);
        registry = new CourierRegistry(manager, config, vault);
        reputation = new ReputationRegistry(manager);
        hub = new DeliveryHub(manager, config, registry, vault, reputation, BID_DEPOSIT);

        vm.startPrank(admin);
        manager.grantRole(manager.VAULT_CONTROLLER_ROLE(), address(registry));
        manager.grantRole(manager.VAULT_CONTROLLER_ROLE(), address(hub));
        manager.grantRole(manager.REGISTRY_CONTROLLER_ROLE(), address(hub));
        manager.grantRole(manager.REPUTATION_REPORTER_ROLE(), address(hub));
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

    function _readyForPickup() internal returns (uint256 id) {
        return _readyForPickupFor(customer);
    }

    function _readyForPickupFor(address who) internal returns (uint256 id) {
        CoverageQuote.Quote memory q = buildQuote(config, who, 1, DECLARED_VALUE);
        bytes memory qsig = signQuote(hub, q);
        vm.prank(who);
        id = hub.createDelivery(q, qsig);

        vm.prank(courier);
        hub.placeBid(id, ASK, RETURN_ASK, 30, uint64(block.timestamp + 1 hours));

        uint32 version = hub.bidOf(id, courier).termsVersion;
        vm.prank(who);
        hub.selectCourier(id, courier, version);

        uint256 amount = hub.customerFundingAmount(id);
        vm.deal(who, who.balance + amount);
        vm.prank(who);
        hub.fundAsCustomer{value: amount}(id);
        vm.prank(courier);
        hub.fundAsCourier(id);
    }

    function _submit(uint256 id, PickupProof.Acceptance memory a, bytes memory sig) internal {
        vm.prank(courier);
        hub.confirmPickup(id, a, sig);
    }

    // -------------------------------------------------------- happy path

    function test_ValidAcceptance_MovesToInTransit() public {
        uint256 id = _readyForPickup();
        PickupProof.Acceptance memory a = buildAcceptance(id, courier);
        bytes memory sig = signAcceptance(hub, a, senderKey(0));

        _submit(id, a, sig);

        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.InTransit));
        assertEq(registry.courierOf(courier).activeCustody, 1, "custody opens on pickup");
        assertTrue(hub.pickupNonceUsed(customer, a.nonce), "nonce burned");
    }

    /// @dev sec. 11: pickup goes straight to IN_TRANSIT, no extra transaction.
    function test_ValidAcceptance_EmitsConsumption() public {
        uint256 id = _readyForPickup();
        PickupProof.Acceptance memory a = buildAcceptance(id, courier);
        bytes memory sig = signAcceptance(hub, a, senderKey(0));
        bytes32 digest = pickupDigest(hub, a);

        vm.expectEmit(true, true, true, true, address(hub));
        emit PickupProofVerifier.PickupAcceptanceConsumed(id, customer, courier, a.nonce, digest);
        _submit(id, a, sig);
    }

    // --------------------------------------- the six sec. 12 checks, one by one

    /// @dev 1/6 — correct delivery. An acceptance for another delivery is rejected.
    function test_Rejects_WrongDelivery() public {
        uint256 idA = _readyForPickup();
        uint256 idB = _readyForPickup();

        PickupProof.Acceptance memory a = buildAcceptance(idB, courier);
        bytes memory sig = signAcceptance(hub, a, senderKey(0));

        vm.expectRevert(abi.encodeWithSelector(PickupProofVerifier.PickupProofWrongDelivery.selector, idA, idB));
        _submit(idA, a, sig);
    }

    /// @dev 2/6 — correct action. A signature gathered for another step is rejected.
    function test_Rejects_WrongAction() public {
        uint256 id = _readyForPickup();
        PickupProof.Acceptance memory a = buildAcceptance(id, courier);
        a.action = keccak256("MONOSFER.RETURN");
        bytes memory sig = signAcceptance(hub, a, senderKey(0));

        vm.expectRevert(
            abi.encodeWithSelector(
                PickupProofVerifier.PickupProofWrongAction.selector, PickupProof.PICKUP_ACTION, a.action
            )
        );
        _submit(id, a, sig);
    }

    /// @dev 3/6 — correct courier. The sender attests to who took the package.
    function test_Rejects_WrongCourier() public {
        uint256 id = _readyForPickup();
        PickupProof.Acceptance memory a = buildAcceptance(id, courier2);
        bytes memory sig = signAcceptance(hub, a, senderKey(0));

        vm.expectRevert(abi.encodeWithSelector(PickupProofVerifier.PickupProofWrongCourier.selector, courier, courier2));
        _submit(id, a, sig);
    }

    /// @dev 4/6 — expiry.
    function test_Rejects_Expired() public {
        uint256 id = _readyForPickup();
        uint64 expiresAt = uint64(block.timestamp) + 60;
        PickupProof.Acceptance memory a = buildAcceptanceWithExpiry(id, courier, expiresAt, 0);
        bytes memory sig = signAcceptance(hub, a, senderKey(0));

        vm.warp(expiresAt + 1);
        vm.expectRevert(abi.encodeWithSelector(PickupProofVerifier.PickupProofExpired.selector, expiresAt));
        _submit(id, a, sig);
    }

    /// @dev The last valid second is still valid — the boundary is inclusive.
    function test_Accepts_OnFinalSecondOfValidity() public {
        uint256 id = _readyForPickup();
        uint64 expiresAt = uint64(block.timestamp) + 60;
        PickupProof.Acceptance memory a = buildAcceptanceWithExpiry(id, courier, expiresAt, 0);
        bytes memory sig = signAcceptance(hub, a, senderKey(0));

        vm.warp(expiresAt);
        _submit(id, a, sig);
        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.InTransit));
    }

    /// @dev 5/6 — nonce uniqueness. A nonce is spent for that sender, everywhere.
    function test_Rejects_ReusedNonce() public {
        uint256 idA = _readyForPickup();
        uint256 idB = _readyForPickup();

        PickupProof.Acceptance memory a = buildAcceptance(idA, courier);
        bytes memory sig = signAcceptance(hub, a, senderKey(0));
        _submit(idA, a, sig);

        // Same nonce, different delivery: still refused.
        PickupProof.Acceptance memory b = buildAcceptance(idB, courier);
        b.nonce = a.nonce;
        bytes memory sigB = signAcceptance(hub, b, senderKey(0));

        vm.expectRevert(abi.encodeWithSelector(PickupProofVerifier.PickupProofNonceUsed.selector, customer, a.nonce));
        _submit(idB, b, sigB);
    }

    /// @dev 6/6 — correct signer. Only the sender of *this* delivery authorises it.
    function test_Rejects_SignatureFromAnotherKey() public {
        uint256 id = _readyForPickup();
        PickupProof.Acceptance memory a = buildAcceptance(id, courier);
        bytes memory sig = signAcceptance(hub, a, senderKey(9));

        vm.expectRevert(
            abi.encodeWithSelector(PickupProofVerifier.PickupProofSignatureInvalid.selector, pickupDigest(hub, a))
        );
        _submit(id, a, sig);
    }

    /**
     * @dev The courier signing their own pickup is exactly what sec. 12 rules
     *      out: it would be the same unilateral claim as an unsigned call. The
     *      signature here is genuinely the courier's own key.
     */
    function test_Rejects_CourierSelfSignedAcceptance() public {
        uint256 id = _readyForPickup();
        PickupProof.Acceptance memory a = buildAcceptance(id, courier);
        bytes memory sig = signAcceptance(hub, a, COURIER_KEY);

        vm.expectRevert(
            abi.encodeWithSelector(PickupProofVerifier.PickupProofSignatureInvalid.selector, pickupDigest(hub, a))
        );
        _submit(id, a, sig);
    }

    /**
     * @dev The cost of requiring the sender's signature: a sender who refuses to
     *      sign stalls the handover. Nothing is stuck — the pickup window runs
     *      out, `poke` cancels, the customer's escrow returns and the courier's
     *      coverage is released unslashed. Recording it here because it is a real
     *      behavioural consequence of P2.1, not an oversight.
     */
    function test_SenderRefusingToSign_StallsThenCancelsCleanly() public {
        uint256 id = _readyForPickup();
        uint256 escrow = hub.customerFundingAmount(id);

        vm.warp(block.timestamp + config.pickupWindow() + 1);
        hub.poke(id);

        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.Cancelled));
        assertEq(vault.claimableOf(customer), escrow, "escrow returns to the customer");
        assertEq(registry.courierOf(courier).reserved, 0, "coverage released, not slashed");
        assertEq(registry.courierOf(courier).activeCustody, 0);
    }

    // ------------------------------------------------------------- replay

    /// @dev Invariant sec. 33-7. The same delivery cannot be picked up twice.
    function test_Rejects_ReplayOnSameDelivery() public {
        uint256 id = _readyForPickup();
        PickupProof.Acceptance memory a = buildAcceptance(id, courier);
        bytes memory sig = signAcceptance(hub, a, senderKey(0));
        _submit(id, a, sig);

        // Rejected on state before the proof is even examined.
        vm.expectRevert();
        _submit(id, a, sig);
    }

    /// @dev sec. 47: a proof captured on one delivery is worthless on another.
    function test_Rejects_ReplayAcrossDeliveries() public {
        uint256 idA = _readyForPickup();
        uint256 idB = _readyForPickup();

        PickupProof.Acceptance memory a = buildAcceptance(idA, courier);
        bytes memory sig = signAcceptance(hub, a, senderKey(0));
        _submit(idA, a, sig);

        vm.expectRevert(abi.encodeWithSelector(PickupProofVerifier.PickupProofWrongDelivery.selector, idB, idA));
        _submit(idB, a, sig);
    }

    /// @dev An acceptance signed by a different sender cannot be borrowed.
    function test_Rejects_AcceptanceFromAnotherSender() public {
        uint256 id = _readyForPickup();
        address otherSender = senderAddress(1);
        vm.deal(otherSender, 1_000 ether);
        uint256 otherId = _readyForPickupFor(otherSender);

        PickupProof.Acceptance memory a = buildAcceptance(id, courier);
        bytes memory sig = signAcceptance(hub, a, senderKey(1));

        vm.expectRevert(
            abi.encodeWithSelector(PickupProofVerifier.PickupProofSignatureInvalid.selector, pickupDigest(hub, a))
        );
        _submit(id, a, sig);

        // The other sender's own delivery is unaffected.
        assertEq(uint8(hub.deliveryOf(otherId).state), uint8(DeliveryHub.State.ReadyForPickup));
    }

    // ----------------------------------------------------- caller and state

    /// @dev A valid acceptance does not let a third party move the package.
    function test_Rejects_SubmissionByNonCourier() public {
        uint256 id = _readyForPickup();
        PickupProof.Acceptance memory a = buildAcceptance(id, courier);
        bytes memory sig = signAcceptance(hub, a, senderKey(0));

        vm.expectRevert(abi.encodeWithSelector(DeliveryHub.NotCourier.selector, courier2));
        vm.prank(courier2);
        hub.confirmPickup(id, a, sig);
    }

    /// @dev A rejected proof must leave the delivery exactly where it was.
    function test_FailedProof_LeavesStateAndNonceUntouched() public {
        uint256 id = _readyForPickup();
        PickupProof.Acceptance memory a = buildAcceptance(id, courier);
        bytes memory sig = signAcceptance(hub, a, senderKey(9));

        vm.expectRevert();
        _submit(id, a, sig);

        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.ReadyForPickup));
        assertFalse(hub.pickupNonceUsed(customer, a.nonce), "a failed proof must not burn the nonce");
        assertEq(registry.courierOf(courier).activeCustody, 0);
    }

    /// @dev An unused acceptance leaves its nonce free to be signed again.
    function test_ExpiredAcceptance_LeavesNonceReusable() public {
        uint256 id = _readyForPickup();
        uint64 expiresAt = uint64(block.timestamp) + 60;
        PickupProof.Acceptance memory a = buildAcceptanceWithExpiry(id, courier, expiresAt, 0);

        vm.warp(expiresAt + 1);
        assertFalse(hub.pickupNonceUsed(customer, a.nonce));

        PickupProof.Acceptance memory b = buildAcceptance(id, courier);
        b.nonce = a.nonce;
        bytes memory sigB = signAcceptance(hub, b, senderKey(0));
        _submit(id, b, sigB);

        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.InTransit));
    }

    // ------------------------------------------------------------- ERC-1271

    /// @dev sec. 12: a smart-account sender must work exactly like an EOA one.
    function test_SmartAccountSender_Accepted() public {
        SmartAccountSender account = new SmartAccountSender(senderAddress(0));
        vm.deal(address(account), 1_000 ether);
        uint256 id = _readyForPickupFor(address(account));

        PickupProof.Acceptance memory a = buildAcceptance(id, courier);
        bytes memory sig = signAcceptance(hub, a, senderKey(0));

        _submit(id, a, sig);

        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.InTransit));
        assertTrue(hub.pickupNonceUsed(address(account), a.nonce), "nonce burned against the account");
    }

    /// @dev The smart account must reject what its owner did not sign.
    function test_SmartAccountSender_RejectsForeignSignature() public {
        SmartAccountSender account = new SmartAccountSender(senderAddress(0));
        vm.deal(address(account), 1_000 ether);
        uint256 id = _readyForPickupFor(address(account));

        PickupProof.Acceptance memory a = buildAcceptance(id, courier);
        bytes memory sig = signAcceptance(hub, a, senderKey(1));

        vm.expectRevert();
        _submit(id, a, sig);
    }

    // ------------------------------------------------------- typed data

    /**
     * @dev The fixture derives the digest independently of the contract. If the
     *      type string or the field order ever drift apart, this is where it
     *      surfaces — rather than as a signature every wallet produces and no
     *      contract accepts.
     */
    function test_HashMatchesIndependentDerivation() public {
        uint256 id = _readyForPickup();
        PickupProof.Acceptance memory a = buildAcceptance(id, courier);
        assertEq(hub.hashPickupAcceptance(a), pickupDigest(hub, a));
    }

    /// @dev sec. 12: the domain binds the chain and this deployment.
    function test_DomainIsBoundToChainAndDeployment() public {
        uint256 id = _readyForPickup();
        PickupProof.Acceptance memory a = buildAcceptance(id, courier);
        bytes32 here = hub.hashPickupAcceptance(a);

        DeliveryHub other = new DeliveryHub(manager, config, registry, vault, reputation, BID_DEPOSIT);
        assertTrue(here != other.hashPickupAcceptance(a), "same acceptance must not hash equal on another deployment");

        (, string memory name, string memory version, uint256 chainId, address verifyingContract,,) = hub.eip712Domain();
        assertEq(name, "MONOSFER");
        assertEq(version, "1");
        assertEq(chainId, block.chainid);
        assertEq(verifyingContract, address(hub));
    }

    /// @dev The action constant is exposed so backends cannot guess it wrong.
    function test_ActionConstantIsPublished() public view {
        assertEq(hub.pickupAction(), keccak256("MONOSFER.PICKUP"));
    }

    // ----------------------------------------------------------------- fuzz

    /// @dev No random signature blob authorises a handover.
    function testFuzz_RandomSignatureNeverAccepted(bytes calldata blob) public {
        vm.assume(blob.length <= 200);
        uint256 id = _readyForPickup();
        PickupProof.Acceptance memory a = buildAcceptance(id, courier);

        vm.prank(courier);
        try hub.confirmPickup(id, a, blob) {
            fail();
        } catch {}

        assertEq(uint8(hub.deliveryOf(id).state), uint8(DeliveryHub.State.ReadyForPickup));
    }

    /// @dev No key other than the sender's authorises a handover.
    function testFuzz_OnlySenderKeyAuthorises(uint256 key) public {
        key = bound(key, 1, type(uint128).max);
        vm.assume(vm.addr(key) != customer);

        uint256 id = _readyForPickup();
        PickupProof.Acceptance memory a = buildAcceptance(id, courier);
        bytes memory sig = signAcceptance(hub, a, key);

        vm.prank(courier);
        try hub.confirmPickup(id, a, sig) {
            fail();
        } catch {}
    }

    /// @dev Any tampering with a signed field invalidates the signature.
    function testFuzz_TamperedNonceNeverAccepted(uint256 tamperedNonce) public {
        uint256 id = _readyForPickup();
        PickupProof.Acceptance memory a = buildAcceptance(id, courier);
        vm.assume(tamperedNonce != a.nonce);

        bytes memory sig = signAcceptance(hub, a, senderKey(0));
        a.nonce = tamperedNonce;

        vm.prank(courier);
        try hub.confirmPickup(id, a, sig) {
            fail();
        } catch {}
    }
}
