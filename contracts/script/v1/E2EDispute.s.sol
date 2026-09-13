// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {ProtocolConfig} from "../../src/v1/config/ProtocolConfig.sol";
import {SettlementVault} from "../../src/v1/vault/SettlementVault.sol";
import {CourierRegistry} from "../../src/v1/registry/CourierRegistry.sol";
import {DeliveryHub} from "../../src/v1/hub/DeliveryHub.sol";
import {JurorPool} from "../../src/v1/dispute/JurorPool.sol";
import {DisputeCourt} from "../../src/v1/dispute/DisputeCourt.sol";
import {IRandomnessAdapter} from "../../src/v1/randomness/IRandomnessAdapter.sol";
import {CoverageQuote} from "../../src/v1/risk/CoverageQuote.sol";
import {PickupProof} from "../../src/v1/proof/PickupProof.sol";

/**
 * @title E2EDispute
 * @notice sec. 46's third flow — dispute, jury, appeal, resolve — one stage per
 *         invocation, because the stages are separated by real time.
 * @dev Run against `DeployCompressed`, whose windows sit at the ten-minute
 *      floor. Everything else is the production code: the same rules, the same
 *      signatures, the same payouts, and Pyth Entropy answering for real.
 *
 *      Stages, and what has to have happened before each:
 *
 *      | STAGE | Needs |
 *      |---|---|
 *      | `stake`   | nothing; seats five jurors and the courier |
 *      | `open`    | nothing; delivery to transit, then dispute opened |
 *      | `draw`    | the evidence window to have passed |
 *      | `seat`    | the provider to have answered |
 *      | `commit`  | a seated panel |
 *      | `reveal`  | the commit window to have passed |
 *      | `close`   | the reveal window to have passed |
 *      | `appeal`  | a ruling, inside the appeal window |
 *      | `settle`  | a ruling, after the appeal window |
 *
 *      One stage per run rather than one long script: every stage waits on a
 *      deadline the chain enforces, and a script that sleeps through them would
 *      hold a broadcast open for an hour and lose to the first RPC hiccup.
 */
contract E2EDisputeScript is Script {
    error UnknownStage(string stage);
    error Expected(string what, uint256 expected, uint256 actual);

    ProtocolConfig internal config;
    CourierRegistry internal registry;
    SettlementVault internal vault;
    DeliveryHub internal hub;
    JurorPool internal pool;
    DisputeCourt internal court;

    uint256 internal customerKey;
    uint256 internal courierKey;
    uint256 internal quoteKey;
    address internal customer;
    address internal courier;

    /// @dev Five jurors: enough for round one's three and round two's five.
    uint256 internal constant JUROR_COUNT = 5;

    function run() external {
        customerKey = vm.envUint("CUSTOMER_KEY");
        courierKey = vm.envUint("COURIER_KEY");
        quoteKey = vm.envUint("RISK_QUOTE_SIGNER_KEY");

        config = ProtocolConfig(vm.envAddress("PROTOCOL_CONFIG"));
        registry = CourierRegistry(payable(vm.envAddress("COURIER_REGISTRY")));
        vault = SettlementVault(payable(vm.envAddress("SETTLEMENT_VAULT")));
        hub = DeliveryHub(vm.envAddress("DELIVERY_HUB"));
        pool = JurorPool(payable(vm.envAddress("JUROR_POOL")));
        court = DisputeCourt(payable(vm.envAddress("DISPUTE_COURT")));

        customer = vm.addr(customerKey);
        courier = vm.addr(courierKey);

        string memory stage = vm.envString("STAGE");
        bytes32 s = keccak256(bytes(stage));

        if (s == keccak256("stake")) return _stake();
        if (s == keccak256("open")) return _open();
        if (s == keccak256("draw")) return _draw();
        if (s == keccak256("seat")) return _seat();
        if (s == keccak256("commit")) return _commit();
        if (s == keccak256("reveal")) return _reveal();
        if (s == keccak256("close")) return _close();
        if (s == keccak256("appeal")) return _appeal();
        if (s == keccak256("settle")) return _settle();
        revert UnknownStage(stage);
    }

    // --------------------------------------------------------------- stake

    function _stake() internal {
        vm.startBroadcast(courierKey);
        if (registry.courierOf(courier).stake == 0) {
            registry.depositStake{value: config.courierBaseDeposit() + 2 ether}();
        }
        vm.stopBroadcast();

        uint256 min = config.minJurorStake();
        for (uint256 i = 0; i < JUROR_COUNT; i++) {
            uint256 key = _jurorKey(i);
            address juror = vm.addr(key);
            if (pool.jurorOf(juror).active) continue;
            vm.startBroadcast(key);
            if (pool.jurorOf(juror).stake == 0) pool.stake{value: min * 2}();
            pool.activate();
            vm.stopBroadcast();
        }
        console2.log("jurors standing:", pool.eligibleCount());
        if (pool.eligibleCount() < JUROR_COUNT) {
            revert Expected("jurors", JUROR_COUNT, pool.eligibleCount());
        }
    }

    // ---------------------------------------------------------------- open

    function _open() internal {
        uint96 declaredValue = 1 ether;
        CoverageQuote.Quote memory q = CoverageQuote.Quote({
            customer: customer,
            riskTier: 1,
            declaredValue: declaredValue,
            requiredCoverage: uint96((uint256(declaredValue) * config.coverageBpsForTier(1)) / 10_000),
            issuedAt: uint64(block.timestamp),
            expiresAt: uint64(block.timestamp + config.riskQuoteValidity()),
            salt: keccak256(abi.encode("e2e-dispute", block.timestamp))
        });

        vm.startBroadcast(customerKey);
        uint256 id = hub.createDelivery(q, _sign(quoteKey, CoverageQuote.hash(q)));
        vm.stopBroadcast();

        vm.startBroadcast(courierKey);
        hub.placeBid(id, 0.4 ether, 0.1 ether, 60, uint64(block.timestamp + 1 hours));
        vm.stopBroadcast();

        uint32 version = hub.bidOf(id, courier).termsVersion;
        vm.startBroadcast(customerKey);
        hub.selectCourier(id, courier, version);
        hub.fundAsCustomer{value: hub.customerFundingAmount(id)}(id);
        vm.stopBroadcast();

        vm.startBroadcast(courierKey);
        hub.fundAsCourier(id);
        vm.stopBroadcast();

        PickupProof.Acceptance memory acc = PickupProof.Acceptance({
            deliveryId: id,
            courier: courier,
            action: PickupProof.PICKUP_ACTION,
            nonce: uint256(keccak256(abi.encode("pickup", id, block.timestamp))),
            expiresAt: uint64(block.timestamp + 1 hours)
        });
        vm.startBroadcast(courierKey);
        hub.confirmPickup(id, acc, _sign(customerKey, PickupProof.hash(acc)));
        vm.stopBroadcast();

        uint256 cost = uint256(config.arbitrationFee(1)) + config.disputeBond(1);
        vm.startBroadcast(customerKey);
        uint256 disputeId = court.open{value: cost}(id);
        vm.stopBroadcast();

        console2.log("deliveryId   ", id);
        console2.log("disputeId    ", disputeId);
        console2.log("evidence ends", court.disputeOf(disputeId).phaseDeadline);
    }

    // ----------------------------------------------------- the jury stages

    function _draw() internal {
        uint256 id = vm.envUint("DISPUTE_ID");
        uint256 fee = court.randomness().fee();
        vm.startBroadcast(customerKey);
        court.requestDraw{value: fee}(id);
        vm.stopBroadcast();
        console2.log("draw requested, requestId", court.disputeOf(id).drawRequestId);
    }

    function _seat() internal {
        uint256 id = vm.envUint("DISPUTE_ID");
        vm.startBroadcast(customerKey);
        court.seatPanel(id);
        vm.stopBroadcast();
        address[] memory panel = court.panelOf(id);
        console2.log("panel seated, size", panel.length, "round", court.disputeOf(id).round);
    }

    /// @dev Everyone votes `Customer100` in round one, so the appeal has
    ///      something to disagree with.
    function _commit() internal {
        uint256 id = vm.envUint("DISPUTE_ID");
        uint8 round = court.disputeOf(id).round;
        DisputeCourt.Ruling ruling = _rulingFor(round);
        address[] memory panel = court.panelOf(id);

        for (uint256 i = 0; i < panel.length; i++) {
            uint256 key = _keyOf(panel[i]);
            bytes32 h = court.hashVote(id, round, panel[i], ruling, _salt(id, round, i));
            vm.startBroadcast(key);
            court.commitVote(id, h);
            vm.stopBroadcast();
        }
        console2.log("committed", panel.length, "votes; commit ends", court.disputeOf(id).phaseDeadline);
    }

    function _reveal() internal {
        uint256 id = vm.envUint("DISPUTE_ID");
        if (court.disputeOf(id).phase == DisputeCourt.Phase.Commit) {
            vm.startBroadcast(customerKey);
            court.closeCommit(id);
            vm.stopBroadcast();
        }
        uint8 round = court.disputeOf(id).round;
        DisputeCourt.Ruling ruling = _rulingFor(round);
        address[] memory panel = court.panelOf(id);

        for (uint256 i = 0; i < panel.length; i++) {
            vm.startBroadcast(_keyOf(panel[i]));
            court.revealVote(id, ruling, _salt(id, round, i));
            vm.stopBroadcast();
        }
        console2.log("revealed", court.disputeOf(id).revealed, "of", panel.length);
    }

    function _close() internal {
        uint256 id = vm.envUint("DISPUTE_ID");
        vm.startBroadcast(customerKey);
        court.closeReveal(id);
        vm.stopBroadcast();
        DisputeCourt.Dispute memory d = court.disputeOf(id);
        console2.log("round", d.round, "ruling", uint8(d.ruling));
        console2.log("phase", uint8(d.phase), "appeal window ends", d.phaseDeadline);
    }

    /// @dev The courier appeals, because round one went against it.
    function _appeal() internal {
        uint256 id = vm.envUint("DISPUTE_ID");
        uint8 next = court.disputeOf(id).round + 1;
        uint256 cost = uint256(config.arbitrationFee(next)) + config.disputeBond(next);
        vm.startBroadcast(courierKey);
        court.appeal{value: cost}(id);
        vm.stopBroadcast();
        console2.log("appealed to round", court.disputeOf(id).round);
        console2.log("evidence ends", court.disputeOf(id).phaseDeadline);
    }

    function _settle() internal {
        uint256 id = vm.envUint("DISPUTE_ID");
        uint256 deliveryId = court.disputeOf(id).deliveryId;
        uint256 customerBefore = vault.claimableOf(customer);
        uint256 courierBefore = vault.claimableOf(courier);

        vm.startBroadcast(customerKey);
        court.finalise(id);
        vm.stopBroadcast();

        console2.log("delivery state", uint8(hub.deliveryOf(deliveryId).state));
        console2.log("to customer (wei)", vault.claimableOf(customer) - customerBefore);
        console2.log("to courier  (wei)", vault.claimableOf(courier) - courierBefore);
        console2.log("bond back to courier (wei)", court.claimable(courier));
        console2.log("treasury owed (wei)", court.claimable(config.treasury()));
    }

    // ------------------------------------------------------------ helpers

    /// @dev Round one finds for the customer; round two overturns it, so the
    ///      appeal bond's refund path is the one exercised.
    function _rulingFor(uint8 round) internal pure returns (DisputeCourt.Ruling) {
        return round == 1 ? DisputeCourt.Ruling.Customer100 : DisputeCourt.Ruling.Courier100;
    }

    function _jurorKey(uint256 i) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode("monosfer-testnet-juror", i)));
    }

    function _keyOf(address juror) internal pure returns (uint256) {
        for (uint256 i = 0; i < JUROR_COUNT; i++) {
            uint256 key = _jurorKey(i);
            if (vm.addr(key) == juror) return key;
        }
        revert Expected("known juror", 0, uint160(juror));
    }

    function _salt(uint256 id, uint8 round, uint256 i) internal pure returns (bytes32) {
        return keccak256(abi.encode("salt", id, round, i));
    }

    function _sign(uint256 key, bytes32 structHash) internal view returns (bytes memory) {
        bytes32 digest = keccak256(abi.encodePacked(hex"1901", hub.quoteDomainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }
}
