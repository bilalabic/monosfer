// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title IRandomnessAdapter
 * @notice The only randomness surface the dispute court is allowed to know about.
 * @dev Baseline refs: sec. 29 (provider abstraction, dynamic fee, pass-through
 *      fee, callback records only, no blockhash fallback).
 *
 *      ## Why the court pulls instead of being called back
 *
 *      sec. 29 says the provider's callback must only record randomness and must
 *      not settle a dispute. This interface goes one step further: the provider
 *      never reaches the court at all. The adapter records the value and the
 *      court reads it in a later transaction of its own.
 *
 *      That closes the question rather than answering it. A callback that is
 *      merely *supposed* to record can still reenter, run out of gas partway, or
 *      grow a settlement path in a future version. One that does not exist cannot.
 *
 *      It also answers liveness: if a provider never delivers, `isFulfilled`
 *      simply stays false and the court can time the draw out on its own clock.
 *      Nothing is stranded waiting for a call that is not coming.
 *
 *      ## What an implementation must guarantee
 *
 *      - `fee()` is queried live, never cached or hardcoded (sec. 29).
 *      - `request` forwards exactly the provider's fee and refunds any excess,
 *        so the cost is pass-through rather than a margin.
 *      - A fulfilled request's randomness never changes.
 *      - Nothing derives randomness from block data. A miner-influenced value is
 *        not randomness for juror selection and sec. 29 rules it out by name.
 */
interface IRandomnessAdapter {
    event RandomnessRequested(uint64 indexed requestId, address indexed requester, uint256 feePaid);
    event RandomnessRecorded(uint64 indexed requestId, bytes32 randomness);

    /// @notice The provider's current fee, in wei. Queried live (sec. 29).
    function fee() external view returns (uint256);

    /**
     * @notice Ask the provider for a random value.
     * @param seed Caller-supplied entropy, mixed with the provider's own so that
     *        neither side alone determines the result.
     * @return requestId Handle to read the value back with.
     */
    function request(bytes32 seed) external payable returns (uint64 requestId);

    /// @notice The recorded value, and whether it has arrived yet.
    function randomnessOf(uint64 requestId) external view returns (bytes32 value, bool fulfilled);

    /// @notice Whether `requestId` has a value. Cheaper than reading both.
    function isFulfilled(uint64 requestId) external view returns (bool);

    /// @notice Who paid for `requestId`. Only they may read it as theirs.
    function requesterOf(uint64 requestId) external view returns (address);
}
