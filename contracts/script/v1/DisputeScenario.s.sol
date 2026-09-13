// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {ProtocolConfig} from "../../src/v1/config/ProtocolConfig.sol";
import {CourierRegistry} from "../../src/v1/registry/CourierRegistry.sol";
import {DeliveryHub} from "../../src/v1/hub/DeliveryHub.sol";
import {DisputeCourt} from "../../src/v1/dispute/DisputeCourt.sol";
import {CoverageQuote} from "../../src/v1/risk/CoverageQuote.sol";
import {PickupProof} from "../../src/v1/proof/PickupProof.sol";

/**
 * @title DisputeScenario
 * @notice Drives one delivery to the point a jury can take it, on a live chain.
 * @dev Baseline refs: sec. 26 (what a dispute is for), sec. 28 (the fee and bond
 *      schedule), sec. 46 (end-to-end scenarios).
 *
 *      ## What this can and cannot prove on a live chain
 *
 *      The reachable part is everything up to and including the court taking the
 *      delivery: funding, pickup, opening a dispute, the schedule being charged
 *      and the hub moving to `Disputed`.
 *
 *      The rest of sec. 28's path is **structurally unverifiable in one
 *      session**, and saying so is more useful than pretending otherwise. The
 *      windows are measured in days — three for evidence, one each for commit
 *      and reveal, two for an appeal — and a live chain has no `vm.warp`. The
 *      same honest limit already applies to the governance timelocks: what a
 *      live chain can prove is that the deadline is *enforced*, and the local
 *      suite proves what happens when it passes.
 *
 *      Rejections are checked separately with `cast call`, because a script that
 *      broadcasts a batch will not include a transaction it knows will revert.
 */
contract DisputeScenarioScript is Script {
    error Unexpected(string what);

    function run() external {
        uint256 customerKey = vm.envUint("CUSTOMER_KEY");
        uint256 courierKey = vm.envUint("COURIER_KEY");
        uint256 quoteSignerKey = vm.envUint("RISK_QUOTE_SIGNER_KEY");

        ProtocolConfig config = ProtocolConfig(vm.envAddress("PROTOCOL_CONFIG"));
        CourierRegistry registry = CourierRegistry(payable(vm.envAddress("COURIER_REGISTRY")));
        DeliveryHub hub = DeliveryHub(vm.envAddress("DELIVERY_HUB"));
        DisputeCourt court = DisputeCourt(payable(vm.envAddress("DISPUTE_COURT")));

        address customer = vm.addr(customerKey);
        address courier = vm.addr(courierKey);

        // ---------------------------------------------------------- stake
        vm.startBroadcast(courierKey);
        if (registry.courierOf(courier).stake == 0) {
            registry.depositStake{value: config.courierBaseDeposit() + 3 ether}();
        }
        vm.stopBroadcast();
        console2.log("1. courier stake        ", registry.courierOf(courier).stake);

        // ------------------------------------------------------- delivery
        uint96 declaredValue = 2 ether;
        CoverageQuote.Quote memory q = CoverageQuote.Quote({
            customer: customer,
            riskTier: 1,
            declaredValue: declaredValue,
            requiredCoverage: uint96((uint256(declaredValue) * config.coverageBpsForTier(1)) / 10_000),
            issuedAt: uint64(block.timestamp),
            expiresAt: uint64(block.timestamp + config.riskQuoteValidity()),
            salt: keccak256(abi.encode("monosfer-p4-scenario", block.timestamp))
        });
        bytes memory qsig = _sign(quoteSignerKey, hub.quoteDomainSeparator(), CoverageQuote.hash(q));

        vm.startBroadcast(customerKey);
        uint256 deliveryId = hub.createDelivery(q, qsig);
        vm.stopBroadcast();
        console2.log("2. deliveryId           ", deliveryId);

        // ------------------------------------------------------------ bid
        vm.startBroadcast(courierKey);
        hub.placeBid(deliveryId, 0.2 ether, 0.05 ether, 60, uint64(block.timestamp + 1 hours));
        vm.stopBroadcast();

        uint32 version = hub.bidOf(deliveryId, courier).termsVersion;
        vm.startBroadcast(customerKey);
        hub.selectCourier(deliveryId, courier, version);
        vm.stopBroadcast();
        console2.log("3. courier selected, terms version", version);

        // -------------------------------------------------------- funding
        uint256 amount = hub.customerFundingAmount(deliveryId);
        vm.startBroadcast(customerKey);
        hub.fundAsCustomer{value: amount}(deliveryId);
        vm.stopBroadcast();
        vm.startBroadcast(courierKey);
        hub.fundAsCourier(deliveryId);
        vm.stopBroadcast();
        console2.log("4. escrow funded        ", amount);

        // --------------------------------------------------------- pickup
        PickupProof.Acceptance memory acc = PickupProof.Acceptance({
            deliveryId: deliveryId,
            courier: courier,
            action: PickupProof.PICKUP_ACTION,
            nonce: uint256(keccak256(abi.encode("pickup", deliveryId, block.timestamp))),
            expiresAt: uint64(block.timestamp + 1 hours)
        });
        bytes memory asig = _sign(customerKey, hub.quoteDomainSeparator(), PickupProof.hash(acc));

        vm.startBroadcast(courierKey);
        hub.confirmPickup(deliveryId, acc, asig);
        vm.stopBroadcast();
        if (hub.deliveryOf(deliveryId).state != DeliveryHub.State.InTransit) revert Unexpected("not in transit");
        console2.log("5. in transit, disputable");

        // -------------------------------------------------- open a dispute
        uint256 cost = uint256(config.arbitrationFee(1)) + config.disputeBond(1);
        uint256 owedBefore = court.totalOwed();

        vm.startBroadcast(customerKey);
        uint256 disputeId = court.open{value: cost}(deliveryId);
        vm.stopBroadcast();

        if (hub.deliveryOf(deliveryId).state != DeliveryHub.State.Disputed) revert Unexpected("hub did not let go");
        if (court.totalOwed() != owedBefore + cost) revert Unexpected("schedule not charged");
        if (court.bondPayerOf(disputeId, 1) != customer) revert Unexpected("bond payer wrong");

        console2.log("6. disputeId            ", disputeId);
        console2.log("   hub state            Disputed");
        console2.log("   charged (wei)        ", cost);
        console2.log("   court owes (wei)     ", court.totalOwed());
        console2.log("   long stop at         ", hub.deliveryOf(deliveryId).stateDeadline);
    }

    function _sign(uint256 key, bytes32 domain, bytes32 structHash) internal pure returns (bytes memory) {
        bytes32 digest = keccak256(abi.encodePacked(hex"1901", domain, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }
}
