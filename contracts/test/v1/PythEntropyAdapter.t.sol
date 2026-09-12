// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IRandomnessAdapter} from "../../src/v1/randomness/IRandomnessAdapter.sol";
import {PythEntropyAdapter, IEntropyV2} from "../../src/v1/randomness/PythEntropyAdapter.sol";

/**
 * @dev Stands in for Pyth Entropy. The fee moves, because a fee that never moves
 *      would let a cached one pass the tests.
 */
contract MockEntropy is IEntropyV2 {
    uint128 public feeAmount = 0.1 ether;
    address public provider = address(0xEEEE);
    uint64 public nextSequence = 1;
    bool public reverting;

    mapping(uint64 => bytes32) public seedOf;
    mapping(uint64 => uint32) public gasLimitOf;

    function setFee(uint128 f) external {
        feeAmount = f;
    }

    function setReverting(bool r) external {
        reverting = r;
    }

    function getFeeV2() external view returns (uint128) {
        return feeAmount;
    }

    function getDefaultProvider() external view returns (address) {
        return provider;
    }

    function requestV2(address, bytes32 userRandomNumber, uint32 gasLimit) external payable returns (uint64 assigned) {
        require(!reverting, "entropy down");
        require(msg.value == feeAmount, "wrong fee forwarded");
        assigned = nextSequence++;
        seedOf[assigned] = userRandomNumber;
        gasLimitOf[assigned] = gasLimit;
    }

    /// @dev Delivers the callback the way Entropy would.
    function deliver(address adapter, uint64 sequence, bytes32 value) external {
        PythEntropyAdapter(adapter)._entropyCallback(sequence, provider, value);
    }
}

/// @dev A requester that refuses its refund, to show it harms only itself.
contract RefusingRequester {
    PythEntropyAdapter internal immutable adapter;

    constructor(PythEntropyAdapter a) {
        adapter = a;
    }

    function ask(bytes32 seed) external payable returns (uint64) {
        return adapter.request{value: msg.value}(seed);
    }

    receive() external payable {
        revert("no refunds");
    }
}

/**
 * @notice The randomness adapter (sec. 29).
 * @dev The claims that matter: the fee is asked for rather than remembered, the
 *      surplus goes back, the callback touches nothing but its own record, and a
 *      provider that goes quiet leaves no wreckage behind.
 */
contract PythEntropyAdapterTest is Test {
    MockEntropy internal entropy;
    PythEntropyAdapter internal adapter;

    address internal court = address(0xC0C0);
    address internal stranger = address(0xBAD);

    function setUp() public {
        entropy = new MockEntropy();
        adapter = new PythEntropyAdapter(IEntropyV2(address(entropy)));
        vm.deal(court, 100 ether);
        vm.deal(stranger, 100 ether);
    }

    // ------------------------------------------------------------ the fee

    /// @dev sec. 29: the fee is queried, not cached.
    function test_FeeFollowsTheProvider() public {
        assertEq(adapter.fee(), 0.1 ether);
        entropy.setFee(0.25 ether);
        assertEq(adapter.fee(), 0.25 ether, "a cached fee would still read 0.1");
    }

    function test_RequestForwardsExactlyTheCurrentFee() public {
        entropy.setFee(0.3 ether);
        vm.prank(court);
        adapter.request{value: 0.3 ether}(keccak256("seed"));
        // MockEntropy reverts unless msg.value equals its fee, so arriving here
        // is the assertion.
        assertEq(address(entropy).balance, 0.3 ether);
    }

    function test_UnderpaymentRejected() public {
        uint256 required = adapter.fee();
        vm.prank(court);
        vm.expectRevert(abi.encodeWithSelector(PythEntropyAdapter.FeeTooLow.selector, required, required - 1));
        adapter.request{value: required - 1}(keccak256("seed"));
    }

    /// @dev sec. 29: pass-through. The protocol takes no margin.
    function test_ExcessIsRefunded() public {
        uint256 before = court.balance;
        vm.prank(court);
        adapter.request{value: 0.4 ether}(keccak256("seed"));

        assertEq(court.balance, before - 0.1 ether, "only the provider's fee left the caller");
        assertEq(address(adapter).balance, 0, "and the adapter keeps nothing");
    }

    function test_ExactPaymentNeedsNoRefund() public {
        uint256 before = court.balance;
        vm.prank(court);
        adapter.request{value: 0.1 ether}(keccak256("seed"));
        assertEq(court.balance, before - 0.1 ether);
        assertEq(address(adapter).balance, 0);
    }

    /// @dev A caller that cannot take its change learns so immediately.
    function test_RefusedRefundRevertsTheRequest() public {
        RefusingRequester requester = new RefusingRequester(adapter);
        vm.deal(address(requester), 10 ether);

        vm.expectRevert();
        requester.ask{value: 0.5 ether}(keccak256("seed"));

        // Exact payment needs no refund, so the same caller can still request.
        uint64 id = requester.ask{value: 0.1 ether}(keccak256("seed"));
        assertEq(adapter.requesterOf(id), address(requester));
    }

    // ------------------------------------------------------- the callback

    function test_CallbackRecordsTheValue() public {
        vm.prank(court);
        uint64 id = adapter.request{value: 0.1 ether}(keccak256("seed"));

        assertFalse(adapter.isFulfilled(id), "nothing yet");

        vm.expectEmit(true, false, false, true, address(adapter));
        emit IRandomnessAdapter.RandomnessRecorded(id, bytes32(uint256(42)));
        entropy.deliver(address(adapter), id, bytes32(uint256(42)));

        (bytes32 value, bool fulfilled) = adapter.randomnessOf(id);
        assertTrue(fulfilled);
        assertEq(value, bytes32(uint256(42)));
    }

    /// @dev Only the entropy contract may write randomness.
    function test_OnlyEntropyMayCallBack() public {
        vm.prank(court);
        uint64 id = adapter.request{value: 0.1 ether}(keccak256("seed"));

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(PythEntropyAdapter.NotEntropy.selector, stranger));
        adapter._entropyCallback(id, address(0xEEEE), bytes32(uint256(1)));

        assertFalse(adapter.isFulfilled(id), "and nothing was written");
    }

    /// @dev A fulfilled request's value is final.
    function test_SecondCallbackRejected() public {
        vm.prank(court);
        uint64 id = adapter.request{value: 0.1 ether}(keccak256("seed"));
        entropy.deliver(address(adapter), id, bytes32(uint256(7)));

        vm.expectRevert(abi.encodeWithSelector(PythEntropyAdapter.AlreadyFulfilled.selector, id));
        entropy.deliver(address(adapter), id, bytes32(uint256(9)));

        (bytes32 value,) = adapter.randomnessOf(id);
        assertEq(value, bytes32(uint256(7)), "the first value stands");
    }

    /// @dev Two requests are independent records.
    function test_RequestsDoNotInterfere() public {
        vm.startPrank(court);
        uint64 a = adapter.request{value: 0.1 ether}(keccak256("a"));
        uint64 b = adapter.request{value: 0.1 ether}(keccak256("b"));
        vm.stopPrank();

        entropy.deliver(address(adapter), b, bytes32(uint256(99)));

        assertFalse(adapter.isFulfilled(a));
        assertTrue(adapter.isFulfilled(b));
        (bytes32 vb,) = adapter.randomnessOf(b);
        assertEq(vb, bytes32(uint256(99)));
    }

    // ------------------------------------------- provider outage (sec. 47)

    /**
     * @dev A provider that never answers must not leave anything stuck. There is
     *      no lock to hold and no state to corrupt: the request simply stays
     *      unfulfilled, which is what lets the court time it out on its own.
     */
    function test_SilentProviderStrandsNothing() public {
        vm.prank(court);
        uint64 id = adapter.request{value: 0.1 ether}(keccak256("seed"));

        vm.warp(block.timestamp + 365 days);

        assertFalse(adapter.isFulfilled(id), "still waiting, and visibly so");
        assertEq(adapter.requesterOf(id), court, "the record is intact");
        assertEq(address(adapter).balance, 0, "and no value is trapped here");

        // A new request still works; one silent answer does not block the next.
        vm.prank(court);
        uint64 next = adapter.request{value: 0.1 ether}(keccak256("again"));
        assertTrue(next != id);
    }

    /// @dev A provider that reverts on request surfaces immediately.
    function test_ProviderRevertIsNotSwallowed() public {
        entropy.setReverting(true);
        vm.prank(court);
        vm.expectRevert();
        adapter.request{value: 0.1 ether}(keccak256("seed"));
    }

    // ------------------------------------------------- no blockhash (sec. 29)

    /**
     * @dev sec. 29 rules out blockhash-derived randomness by name. Proven by
     *      behaviour rather than by reading the source: the recorded value is
     *      whatever the provider said, on a chain where the block data has
     *      changed underneath it.
     */
    function test_ValueComesFromTheProviderNotTheChain() public {
        vm.prank(court);
        uint64 id = adapter.request{value: 0.1 ether}(keccak256("seed"));

        vm.roll(block.number + 1_000);
        vm.warp(block.timestamp + 7 days);
        vm.prevrandao(bytes32(uint256(0xDEADBEEF)));

        bytes32 fromProvider = keccak256("provider-chose-this");
        entropy.deliver(address(adapter), id, fromProvider);

        (bytes32 value,) = adapter.randomnessOf(id);
        assertEq(value, fromProvider, "recorded verbatim, with no chain data mixed in");
    }

    // ----------------------------------------------------------------- fuzz

    function testFuzz_AnyValueIsRecordedVerbatim(bytes32 value) public {
        vm.prank(court);
        uint64 id = adapter.request{value: 0.1 ether}(keccak256("seed"));
        entropy.deliver(address(adapter), id, value);

        (bytes32 stored, bool fulfilled) = adapter.randomnessOf(id);
        assertTrue(fulfilled);
        assertEq(stored, value);
    }

    function testFuzz_FeeIsAlwaysForwardedExactly(uint96 providerFee, uint96 overpay) public {
        providerFee = uint96(bound(providerFee, 1, 5 ether));
        overpay = uint96(bound(overpay, 0, 5 ether));
        entropy.setFee(providerFee);

        vm.deal(court, 20 ether);
        uint256 before = court.balance;
        vm.prank(court);
        adapter.request{value: uint256(providerFee) + overpay}(keccak256("seed"));

        assertEq(before - court.balance, providerFee, "the caller pays the provider's price, no more");
        assertEq(address(adapter).balance, 0);
    }

    function testFuzz_NobodyButEntropyCanWrite(address caller) public {
        vm.assume(caller != address(entropy) && caller.code.length == 0);
        vm.prank(court);
        uint64 id = adapter.request{value: 0.1 ether}(keccak256("seed"));

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(PythEntropyAdapter.NotEntropy.selector, caller));
        adapter._entropyCallback(id, address(0xEEEE), bytes32(uint256(1)));
    }

    // ------------------------------------------------------- the abstraction

    /// @dev The court sees only the interface; any implementation behind it works.
    function test_AdapterSatisfiesTheInterface() public view {
        IRandomnessAdapter iface = IRandomnessAdapter(address(adapter));
        assertEq(iface.fee(), 0.1 ether);
        assertFalse(iface.isFulfilled(1));
    }
}
