// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IRandomnessAdapter} from "./IRandomnessAdapter.sol";

/**
 * @dev The slice of Pyth's Entropy V2 this adapter uses. Declared here rather
 *      than vendoring the SDK: three functions are the whole dependency, and a
 *      local declaration is a smaller thing to audit than a package.
 */
interface IEntropyV2 {
    function getFeeV2() external view returns (uint128 feeAmount);
    function getDefaultProvider() external view returns (address provider);
    function requestV2(address provider, bytes32 userRandomNumber, uint32 gasLimit)
        external
        payable
        returns (uint64 assignedSequenceNumber);
}

/**
 * @title PythEntropyAdapter
 * @notice Pyth Entropy V2 behind the protocol's randomness interface (sec. 29).
 * @dev Baseline refs: sec. 29.
 *
 *      ## The callback records and returns
 *
 *      Entropy calls `_entropyCallback` — the signature is Pyth's, not ours — and
 *      all it does is write the value and emit. It reaches nothing else: no
 *      dispute, no settlement, no external call. sec. 29 requires that, and
 *      keeping the write here means the requirement is satisfied by the shape of
 *      the code rather than by a promise about what the callback happens to do.
 *
 *      ## The fee is asked for, every time
 *
 *      Entropy's fee moves with gas conditions. It is read immediately before
 *      each request and any excess the caller sent is returned, so the protocol
 *      neither caches a stale figure nor takes a margin (sec. 29).
 *
 *      ## A silent provider costs nothing but time
 *
 *      If Entropy never calls back, the request simply stays unfulfilled. There
 *      is no retry loop holding a lock and no state a stuck request can corrupt;
 *      the court reads `isFulfilled`, sees false, and applies its own timeout.
 *
 *      ## Replacing the provider
 *
 *      The court holds an `IRandomnessAdapter`, so a different provider is a
 *      different adapter at a new address and a config change — the court itself
 *      is not redeployed and contains no Pyth-specific code.
 */
contract PythEntropyAdapter is IRandomnessAdapter {
    /// @notice Gas Entropy is asked to supply for the callback.
    /// @dev The callback writes one slot and emits; this is generous for that and
    ///      still small enough that the provider's quoted fee stays reasonable.
    uint32 public constant CALLBACK_GAS_LIMIT = 120_000;

    IEntropyV2 public immutable entropy;

    struct Record {
        address requester;
        bool fulfilled;
        bytes32 value;
    }

    mapping(uint64 => Record) internal _records;

    error ZeroAddress();
    error FeeTooLow(uint256 required, uint256 provided);
    error NotEntropy(address caller);
    error AlreadyFulfilled(uint64 requestId);
    error RefundFailed(address to, uint256 amount);

    constructor(IEntropyV2 entropy_) {
        if (address(entropy_) == address(0)) revert ZeroAddress();
        entropy = entropy_;
    }

    /// @inheritdoc IRandomnessAdapter
    function fee() public view returns (uint256) {
        return entropy.getFeeV2();
    }

    /// @inheritdoc IRandomnessAdapter
    function request(bytes32 seed) external payable returns (uint64 requestId) {
        uint256 required = entropy.getFeeV2();
        if (msg.value < required) revert FeeTooLow(required, msg.value);

        requestId = entropy.requestV2{value: required}(entropy.getDefaultProvider(), seed, CALLBACK_GAS_LIMIT);
        _records[requestId] = Record({requester: msg.sender, fulfilled: false, value: bytes32(0)});
        emit RandomnessRequested(requestId, msg.sender, required);

        // Pass-through, not a margin: whatever the caller sent beyond the
        // provider's price goes straight back.
        uint256 excess = msg.value - required;
        if (excess > 0) {
            (bool ok,) = msg.sender.call{value: excess}("");
            if (!ok) revert RefundFailed(msg.sender, excess);
        }
    }

    /**
     * @notice Entropy's callback. Records the value and nothing else.
     * @dev The name and parameters are dictated by Pyth's `IEntropyConsumer`;
     *      Entropy calls exactly this. The provider argument is part of that
     *      signature and is deliberately unused — the entropy contract itself is
     *      the authority here, and it is checked.
     */
    function _entropyCallback(uint64 sequence, address, bytes32 randomNumber) external {
        if (msg.sender != address(entropy)) revert NotEntropy(msg.sender);

        Record storage r = _records[sequence];
        if (r.fulfilled) revert AlreadyFulfilled(sequence);

        r.fulfilled = true;
        r.value = randomNumber;
        emit RandomnessRecorded(sequence, randomNumber);
    }

    /// @inheritdoc IRandomnessAdapter
    function randomnessOf(uint64 requestId) external view returns (bytes32 value, bool fulfilled) {
        Record storage r = _records[requestId];
        return (r.value, r.fulfilled);
    }

    /// @inheritdoc IRandomnessAdapter
    function isFulfilled(uint64 requestId) external view returns (bool) {
        return _records[requestId].fulfilled;
    }

    /// @inheritdoc IRandomnessAdapter
    function requesterOf(uint64 requestId) external view returns (address) {
        return _records[requestId].requester;
    }
}
