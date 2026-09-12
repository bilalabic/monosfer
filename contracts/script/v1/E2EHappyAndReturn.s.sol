// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {ProtocolConfig} from "../../src/v1/config/ProtocolConfig.sol";
import {SettlementVault} from "../../src/v1/vault/SettlementVault.sol";
import {CourierRegistry} from "../../src/v1/registry/CourierRegistry.sol";
import {DeliveryHub} from "../../src/v1/hub/DeliveryHub.sol";
import {CoverageQuote} from "../../src/v1/risk/CoverageQuote.sol";
import {PickupProof} from "../../src/v1/proof/PickupProof.sol";
import {DeliveryProof} from "../../src/v1/proof/DeliveryProof.sol";

/**
 * @title E2EHappyAndReturn
 * @notice sec. 46's first two end-to-end flows, on a live chain.
 * @dev Flow one is create -> bid -> select -> fund -> pickup -> deliver ->
 *      complete -> claim. Flow two is the same up to transit and then a return
 *      that the sender signs for.
 *
 *      Neither needs a clock to move. The challenge window opens on delivery but
 *      sec. 16 lets the customer confirm early, and a return settles the moment
 *      the sender's acceptance arrives — so both flows run start to finish in one
 *      session, which is why they are here and the jury flow is not.
 *
 *      Every step asserts rather than logs. A script that only prints has told
 *      you what it did, not whether it worked.
 *
 *      ## A caveat about broadcasting this on Monad
 *
 *      `fundAsCustomer` fails from `forge script --broadcast` on this network
 *      while the same call succeeds from `cast send` with an explicit
 *      `--gas-limit`. It failed across four runs, at gas limits from 234k to
 *      626k, with the chain's own estimate at 156k and every replay -- at the
 *      failing block and the one before it -- returning success. The cause is
 *      not established, so the verification log records it as unexplained
 *      rather than guessing.
 *
 *      What this means for running it: use `--gas-estimate-multiplier` and be
 *      ready to finish with `cast send --gas-limit` if a value-bearing call
 *      fails. Do not read `gasUsed` from the receipt to decide whether it ran
 *      out of gas -- on Monad a *successful* transaction also reports
 *      `gasUsed == gasLimit`.
 */
contract E2EHappyAndReturnScript is Script {
    error Expected(string what, uint256 expected, uint256 actual);
    error ExpectedState(string what, uint8 expected, uint8 actual);

    ProtocolConfig internal config;
    CourierRegistry internal registry;
    SettlementVault internal vault;
    DeliveryHub internal hub;

    uint256 internal customerKey;
    uint256 internal courierKey;
    uint256 internal quoteKey;
    uint256 internal podKey;
    address internal customer;
    address internal courier;

    /// @dev Both flows run in one simulation, so `block.timestamp` is the same
    ///      for both. Without a counter their quotes hash identically and the
    ///      second is refused as already redeemed — which is the replay
    ///      protection working, but not on anything this script meant to test.
    uint256 internal salt;

    function run() external {
        customerKey = vm.envUint("CUSTOMER_KEY");
        courierKey = vm.envUint("COURIER_KEY");
        quoteKey = vm.envUint("RISK_QUOTE_SIGNER_KEY");
        podKey = vm.envUint("POD_ATTESTATION_SIGNER_KEY");

        config = ProtocolConfig(vm.envAddress("PROTOCOL_CONFIG"));
        registry = CourierRegistry(payable(vm.envAddress("COURIER_REGISTRY")));
        vault = SettlementVault(payable(vm.envAddress("SETTLEMENT_VAULT")));
        hub = DeliveryHub(vm.envAddress("DELIVERY_HUB"));

        customer = vm.addr(customerKey);
        courier = vm.addr(courierKey);

        _ensureStake();

        // One flow per invocation. Both together are fourteen transactions, and
        // `--slow` waits for each receipt; on a public RPC that ran past the
        // fifteen-minute funding window and the delivery expired underneath the
        // broadcast. The simulation had already passed, which is the point worth
        // remembering: a script that simulates cleanly can still lose a race
        // against a deadline on the real chain.
        uint256 flow = vm.envOr("FLOW", uint256(0));
        if (flow == 1 || flow == 0) _flowOne();
        if (flow == 2 || flow == 0) _flowTwo();

        console2.log("");
        console2.log("=== flow passed on chain ===");
    }

    // ------------------------------------------------------------- flow 1

    function _flowOne() internal {
        console2.log("");
        console2.log("--- flow 1: happy path to claim ---");

        uint256 id = _toInTransit(0.4 ether, 0.1 ether);
        _deliver(id);
        _expectState("delivered", id, DeliveryHub.State.DeliveredPending);

        // sec. 16: the customer need not wait out the challenge window.
        vm.startBroadcast(customerKey);
        hub.confirmDelivery(id);
        vm.stopBroadcast();
        _expectState("completed", id, DeliveryHub.State.Completed);

        uint256 owed = vault.claimableOf(courier);
        if (owed < 0.4 ether) revert Expected("courier credited", 0.4 ether, owed);
        console2.log("  courier owed (wei) ", owed);

        uint256 before = courier.balance;
        vm.startBroadcast(courierKey);
        vault.claim();
        vm.stopBroadcast();

        if (vault.claimableOf(courier) != 0) revert Expected("claim cleared", 0, vault.claimableOf(courier));
        if (courier.balance <= before) revert Expected("courier paid", before + 1, courier.balance);
        console2.log("  claimed, balance rose by (wei)", courier.balance - before);
    }

    // ------------------------------------------------------------- flow 2

    function _flowTwo() internal {
        console2.log("");
        console2.log("--- flow 2: failed delivery to return ---");

        uint96 returnAsk = 0.1 ether;
        uint256 id = _toInTransit(0.4 ether, returnAsk);

        vm.startBroadcast(customerKey);
        hub.requestReturn(id);
        vm.stopBroadcast();
        _expectState("return required", id, DeliveryHub.State.ReturnRequired);

        // sec. 17: the return fee is the courier paying itself, so the sender
        // signs for it. Without this the courier's word would be enough.
        PickupProof.Acceptance memory acc = PickupProof.Acceptance({
            deliveryId: id,
            courier: courier,
            action: PickupProof.RETURN_ACTION,
            nonce: uint256(keccak256(abi.encode("return", id, block.timestamp, salt++))),
            expiresAt: uint64(block.timestamp + 1 hours)
        });
        bytes memory sig = _sign(customerKey, PickupProof.hash(acc));

        uint256 courierBefore = vault.claimableOf(courier);
        // Measured as a change, not against zero. `reserved` is the courier's
        // total across every live delivery, and this chain has an open dispute
        // still holding its own collateral; asserting zero would be asserting
        // something about that dispute instead of about this return.
        uint256 reservedBefore = registry.courierOf(courier).reserved;
        uint256 custodyBefore = registry.courierOf(courier).activeCustody;

        vm.startBroadcast(courierKey);
        hub.confirmReturn(id, acc, sig);
        vm.stopBroadcast();

        _expectState("returned", id, DeliveryHub.State.Returned);
        uint256 gained = vault.claimableOf(courier) - courierBefore;
        if (gained != returnAsk) revert Expected("return fee paid", returnAsk, gained);
        console2.log("  return fee to courier (wei)", gained);

        uint256 freed = reservedBefore - registry.courierOf(courier).reserved;
        if (freed == 0) revert Expected("coverage released", 1, 0);
        if (registry.courierOf(courier).activeCustody != custodyBefore - 1) {
            revert Expected("custody closed", custodyBefore - 1, registry.courierOf(courier).activeCustody);
        }
        console2.log("  coverage freed (wei)", freed);
        console2.log("  custody closed");
    }

    // ------------------------------------------------------------ helpers

    function _ensureStake() internal {
        if (registry.courierOf(courier).stake > 0) return;
        vm.startBroadcast(courierKey);
        registry.depositStake{value: config.courierBaseDeposit() + 2 ether}();
        vm.stopBroadcast();
    }

    function _toInTransit(uint96 ask, uint96 returnAsk) internal returns (uint256 id) {
        uint96 declaredValue = 1 ether;
        CoverageQuote.Quote memory q = CoverageQuote.Quote({
            customer: customer,
            riskTier: 1,
            declaredValue: declaredValue,
            requiredCoverage: uint96((uint256(declaredValue) * config.coverageBpsForTier(1)) / 10_000),
            issuedAt: uint64(block.timestamp),
            expiresAt: uint64(block.timestamp + config.riskQuoteValidity()),
            salt: keccak256(abi.encode("e2e", ask, returnAsk, block.timestamp, salt++))
        });

        bytes memory qsig = _sign(quoteKey, CoverageQuote.hash(q));
        vm.startBroadcast(customerKey);
        id = hub.createDelivery(q, qsig);
        vm.stopBroadcast();

        vm.startBroadcast(courierKey);
        hub.placeBid(id, ask, returnAsk, 60, uint64(block.timestamp + 1 hours));
        vm.stopBroadcast();

        uint32 version = hub.bidOf(id, courier).termsVersion;
        vm.startBroadcast(customerKey);
        hub.selectCourier(id, courier, version);
        vm.stopBroadcast();

        uint256 amount = hub.customerFundingAmount(id);
        vm.startBroadcast(customerKey);
        hub.fundAsCustomer{value: amount}(id);
        vm.stopBroadcast();
        vm.startBroadcast(courierKey);
        hub.fundAsCourier(id);
        vm.stopBroadcast();
        _expectState("ready for pickup", id, DeliveryHub.State.ReadyForPickup);

        PickupProof.Acceptance memory acc = PickupProof.Acceptance({
            deliveryId: id,
            courier: courier,
            action: PickupProof.PICKUP_ACTION,
            nonce: uint256(keccak256(abi.encode("pickup", id, block.timestamp, salt++))),
            expiresAt: uint64(block.timestamp + 1 hours)
        });
        vm.startBroadcast(courierKey);
        hub.confirmPickup(id, acc, _sign(customerKey, PickupProof.hash(acc)));
        vm.stopBroadcast();
        _expectState("in transit", id, DeliveryHub.State.InTransit);
        console2.log("  delivery", id, "in transit; escrow (wei)", amount);
    }

    function _deliver(uint256 id) internal {
        DeliveryProof.Attestation memory a = DeliveryProof.Attestation({
            deliveryId: id,
            courier: courier,
            proofType: DeliveryProof.POD_OTP,
            challengeHash: keccak256(abi.encode("otp", id, block.timestamp)),
            nonce: uint256(keccak256(abi.encode("pod", id, block.timestamp, salt++))),
            issuedAt: uint64(block.timestamp),
            expiresAt: uint64(block.timestamp + config.podAttestationValidity())
        });
        vm.startBroadcast(courierKey);
        hub.submitDeliveryProof(id, a, _sign(podKey, DeliveryProof.hash(a)));
        vm.stopBroadcast();
    }

    function _sign(uint256 key, bytes32 structHash) internal view returns (bytes memory) {
        bytes32 digest = keccak256(abi.encodePacked(hex"1901", hub.quoteDomainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function _expectState(string memory what, uint256 id, DeliveryHub.State want) internal view {
        DeliveryHub.State got = hub.deliveryOf(id).state;
        if (got != want) revert ExpectedState(what, uint8(want), uint8(got));
    }
}
