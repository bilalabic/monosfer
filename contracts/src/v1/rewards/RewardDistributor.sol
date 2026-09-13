// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {ProtocolAccessManager} from "../access/ProtocolAccessManager.sol";
import {ProtocolConfig} from "../config/ProtocolConfig.sol";

/**
 * @title RewardDistributor
 * @notice Per-epoch MON rewards against a published Merkle root (sec. 23).
 * @dev Baseline refs: sec. 23 (weekly epochs, 90-day claim window, 7-day reclaim
 *      delay, only unclaimed budget reclaimable), sec. 48, invariant sec. 33-12
 *      (reward claims cannot exceed the funded epoch budget).
 *
 *      ## Every epoch pays out of its own money
 *
 *      An epoch has to be funded before anything can be claimed from it, and its
 *      claims are checked against *its* balance, not the contract's. Without that
 *      separation a valid proof for one week drains another week's budget — the
 *      claimant looks legitimate, the arithmetic is correct, and the money is
 *      simply gone from somewhere else. sec. 33-12 exists for exactly this.
 *
 *      ## A root is fixed once anyone has relied on it
 *
 *      Before the first claim the treasurer may correct a root: a bad tree caught
 *      early should be fixable. After the first claim it is frozen. Replacing it
 *      then would mean some people were paid under one set of rules and the rest
 *      under another, with no way to tell afterwards which was which.
 *
 *      ## The leaf is hashed twice
 *
 *      `keccak256(keccak256(abi.encode(account, amount)))` — the standard
 *      second-preimage-safe construction, kept from the earlier implementation
 *      because it was already right. A single hash lets an internal node of the
 *      tree be presented as a leaf.
 *
 *      ## Solvency
 *
 *      `address(this).balance >= totalOutstanding` is asserted after every state
 *      change, the same discipline the settlement vault uses. Rewards are a
 *      separate budget from delivery custody and deliberately do not share the
 *      vault: conflating a sponsor's grant with a customer's escrow would give
 *      the vault a second reason to hold money and one more way to be wrong.
 */
contract RewardDistributor is ReentrancyGuard {
    // --------------------------------------------------------------------
    // Types
    // --------------------------------------------------------------------

    /**
     * @param root        Merkle root over (account, amount) leaves.
     * @param funded      MON placed in this epoch.
     * @param claimed     MON already claimed out of it.
     * @param publishedAt When the root was first published; the claim window runs from here.
     * @param reclaimed   Whether the unclaimed remainder has been returned.
     */
    struct Epoch {
        bytes32 root;
        uint128 funded;
        uint128 claimed;
        uint64 publishedAt;
        bool reclaimed;
    }

    // --------------------------------------------------------------------
    // Storage
    // --------------------------------------------------------------------

    ProtocolAccessManager public immutable accessManager;
    ProtocolConfig public immutable config;

    mapping(uint256 => Epoch) internal _epochs;
    mapping(uint256 => mapping(address => bool)) public hasClaimed;

    /// @notice MON this contract still owes across every live epoch.
    uint256 public totalOutstanding;

    // --------------------------------------------------------------------
    // Events and errors
    // --------------------------------------------------------------------

    event EpochFunded(uint256 indexed epochId, address indexed from, uint256 amount, uint256 funded);
    event RootPublished(uint256 indexed epochId, bytes32 root, uint64 publishedAt);
    event RewardClaimed(uint256 indexed epochId, address indexed account, uint256 amount);
    event BudgetReclaimed(uint256 indexed epochId, address indexed to, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error RootNotPublished(uint256 epochId);
    error RootAlreadyRelied(uint256 epochId);
    error ClaimWindowClosed(uint256 epochId, uint64 closesAt);
    error AlreadyClaimed(uint256 epochId, address account);
    error InvalidProof(uint256 epochId, address account);
    error EpochBudgetExceeded(uint256 epochId, uint256 requested, uint256 remaining);
    error ReclaimTooEarly(uint256 epochId, uint64 readyAt);
    error AlreadyReclaimed(uint256 epochId);
    error NothingToReclaim(uint256 epochId);
    error PayoutFailed(address to, uint256 amount);
    error Insolvent();

    // --------------------------------------------------------------------
    // Wiring
    // --------------------------------------------------------------------

    constructor(ProtocolAccessManager accessManager_, ProtocolConfig config_) {
        if (address(accessManager_) == address(0)) revert ZeroAddress();
        if (address(config_) == address(0)) revert ZeroAddress();
        accessManager = accessManager_;
        config = config_;
    }

    modifier onlyTreasurer() {
        accessManager.requireRole(accessManager.TREASURER_ROLE(), msg.sender);
        _;
    }

    /// @dev Mirrors SettlementVault: the contract may hold more than it owes
    ///      (forced sends), never less.
    modifier solvent() {
        _;
        if (address(this).balance < totalOutstanding) revert Insolvent();
    }

    // --------------------------------------------------------------------
    // Funding and roots
    // --------------------------------------------------------------------

    /**
     * @notice Put MON into one epoch's budget.
     * @dev Permissionless by design: sec. 23 names sponsors and grants alongside
     *      the treasury, and requiring a role to *give* money would turn every
     *      sponsor into a governance decision. Who may take money out is where
     *      the authorisation belongs.
     */
    function fundEpoch(uint256 epochId) external payable solvent {
        if (msg.value == 0) revert ZeroAmount();
        Epoch storage e = _epochs[epochId];
        e.funded += uint128(msg.value);
        totalOutstanding += msg.value;
        emit EpochFunded(epochId, msg.sender, msg.value, e.funded);
    }

    /**
     * @notice Publish or correct an epoch's Merkle root.
     * @dev Correctable until the first claim, frozen afterwards.
     */
    function publishRoot(uint256 epochId, bytes32 root) external onlyTreasurer {
        if (root == bytes32(0)) revert ZeroAmount();
        Epoch storage e = _epochs[epochId];
        if (e.claimed > 0) revert RootAlreadyRelied(epochId);

        e.root = root;
        e.publishedAt = uint64(block.timestamp);
        emit RootPublished(epochId, root, e.publishedAt);
    }

    // --------------------------------------------------------------------
    // Claiming
    // --------------------------------------------------------------------

    /**
     * @notice Claim `amount` from `epochId` against the published root.
     * @dev Pays the account named in the leaf, never the caller, so a keeper can
     *      pay the gas for someone without being able to redirect the reward.
     */
    function claim(uint256 epochId, address account, uint256 amount, bytes32[] calldata proof)
        external
        nonReentrant
        solvent
    {
        if (account == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        Epoch storage e = _epochs[epochId];
        if (e.root == bytes32(0)) revert RootNotPublished(epochId);

        uint64 closesAt = e.publishedAt + config.rewardClaimWindow();
        if (block.timestamp > closesAt) revert ClaimWindowClosed(epochId, closesAt);
        if (hasClaimed[epochId][account]) revert AlreadyClaimed(epochId, account);

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(account, amount))));
        if (!MerkleProof.verify(proof, e.root, leaf)) revert InvalidProof(epochId, account);

        // Invariant sec. 33-12. The budget is this epoch's, so a proof from one
        // epoch cannot reach another's money even if the tree were wrong.
        uint256 remaining = uint256(e.funded) - e.claimed;
        if (amount > remaining) revert EpochBudgetExceeded(epochId, amount, remaining);

        hasClaimed[epochId][account] = true;
        e.claimed += uint128(amount);
        totalOutstanding -= amount;

        emit RewardClaimed(epochId, account, amount);
        _payOut(account, amount);
    }

    // --------------------------------------------------------------------
    // Reclaiming
    // --------------------------------------------------------------------

    /**
     * @notice Return an epoch's unclaimed remainder to the treasury (sec. 23).
     * @dev Only after the claim window *and* the reclaim delay, and only what was
     *      never claimed. The delay is there so a budget is not swept out from
     *      under a claim that is already in flight.
     */
    function reclaim(uint256 epochId) external onlyTreasurer nonReentrant solvent {
        Epoch storage e = _epochs[epochId];
        if (e.root == bytes32(0)) revert RootNotPublished(epochId);
        if (e.reclaimed) revert AlreadyReclaimed(epochId);

        uint64 readyAt = e.publishedAt + config.rewardClaimWindow() + config.rewardReclaimDelay();
        if (block.timestamp < readyAt) revert ReclaimTooEarly(epochId, readyAt);

        uint256 remainder = uint256(e.funded) - e.claimed;
        if (remainder == 0) revert NothingToReclaim(epochId);

        e.reclaimed = true;
        e.claimed = e.funded;
        totalOutstanding -= remainder;

        address treasury = config.treasury();
        emit BudgetReclaimed(epochId, treasury, remainder);
        _payOut(treasury, remainder);
    }

    // --------------------------------------------------------------------
    // Reading
    // --------------------------------------------------------------------

    function epochOf(uint256 epochId) external view returns (Epoch memory) {
        return _epochs[epochId];
    }

    /// @notice What is still claimable from `epochId`.
    function remainingBudget(uint256 epochId) external view returns (uint256) {
        Epoch storage e = _epochs[epochId];
        return uint256(e.funded) - e.claimed;
    }

    /// @notice MON held beyond what is owed. Nobody can claim this.
    function surplus() external view returns (uint256) {
        uint256 balance = address(this).balance;
        return balance > totalOutstanding ? balance - totalOutstanding : 0;
    }

    /**
     * @dev Slither reads this as sending to an arbitrary destination because the
     *      address is a parameter. It is not attacker-chosen: `to` is either the
     *      account named in a leaf that was just verified against the treasurer's
     *      published Merkle root, or the treasury address held in ProtocolConfig.
     *      Accounting is written before the call and both entry points are
     *      `nonReentrant`.
     *
     *      The alternative — paying only `msg.sender` — would satisfy the
     *      detector by removing the ability for a keeper to pay a claimant's gas,
     *      which is a real feature for recipients without a MON balance. The
     *      finding is suppressed at this line rather than the rule relaxed for
     *      the codebase, and it is recorded in docs/static-analysis-baseline.md.
     */
    // slither-disable-next-line arbitrary-send-eth
    function _payOut(address to, uint256 amount) internal {
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert PayoutFailed(to, amount);
    }

    /// @dev Value arriving with no epoch named is surplus, not anybody's budget.
    receive() external payable {}
}
