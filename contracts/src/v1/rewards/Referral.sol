// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {ProtocolAccessManager} from "../access/ProtocolAccessManager.sol";

/**
 * @title Referral
 * @notice One referrer per wallet, one reward per wallet, paid on qualification.
 * @dev Baseline refs: sec. 25 (referral rules), sec. 23 (rewards are MON, there
 *      is no protocol token).
 *
 *      ## A referral does not pay because a wallet connected
 *
 *      sec. 25 is explicit: the reward is earned by *doing* something — a first
 *      completed delivery as customer or courier, a first finalised jury round.
 *      Registration is free and proves nothing; qualification is reported by the
 *      protocol contract that witnessed the act.
 *
 *      ## Rewards are claimed, not pushed
 *
 *      Qualification credits the referrer's balance; the referrer withdraws it
 *      themselves. sec. 25 requires that a referral failure never block delivery
 *      settlement, and the way to guarantee that is for settlement never to move
 *      referral money at all. A referrer whose wallet rejects MON, or who never
 *      shows up, holds up nobody.
 *
 *      ## Cycles are impossible by construction, not by search
 *
 *      Every wallet stores its depth in the referral forest: a root is 0, and a
 *      referred wallet is its referrer's depth plus one. Registration requires
 *      the referrer's depth to be below `MAX_DEPTH`, which bounds every chain.
 *      Within that bound the contract walks up from the proposed referrer to
 *      check that the registering wallet is not already an ancestor — the walk is
 *      complete, because a chain cannot be longer than the cap, and its gas is
 *      bounded by the same cap.
 *
 *      Walking without a bound would be the obvious implementation and would make
 *      registration cost grow with the depth of somebody else's tree.
 */
contract Referral is ReentrancyGuard {
    // --------------------------------------------------------------------
    // Constants
    // --------------------------------------------------------------------

    /// @notice Longest referral chain the contract will build.
    uint8 public constant MAX_DEPTH = 32;

    enum Role {
        None,
        Customer,
        Courier,
        Juror
    }

    // --------------------------------------------------------------------
    // Storage
    // --------------------------------------------------------------------

    ProtocolAccessManager public immutable accessManager;

    mapping(address => address) public referrerOf;
    mapping(address => uint8) public depthOf;
    mapping(address => bool) public qualified;
    mapping(address => uint256) public claimable;

    /// @notice The MON a qualification pays the referrer.
    uint128 public rewardAmount;

    /// @notice MON owed to referrers but not yet withdrawn.
    uint256 public totalOwed;

    // --------------------------------------------------------------------
    // Events and errors
    // --------------------------------------------------------------------

    event Registered(address indexed wallet, address indexed referrer, uint8 depth);
    event Qualified(address indexed wallet, address indexed referrer, Role role, uint256 reward);
    event QualifiedWithoutReward(address indexed wallet, Role role, string reason);
    event Claimed(address indexed referrer, uint256 amount);
    event Funded(address indexed from, uint256 amount);
    event RewardAmountSet(uint128 amount);

    error ZeroAddress();
    error ZeroAmount();
    error SelfReferral();
    error AlreadyRegistered(address wallet);
    error ReferrerUnknown(address referrer);
    error ChainTooDeep(uint8 depth);
    error CircularReferral(address wallet, address referrer);
    error AlreadyQualified(address wallet);
    error NothingToClaim(address referrer);
    error PayoutFailed(address to, uint256 amount);
    error Insolvent();

    // --------------------------------------------------------------------
    // Wiring
    // --------------------------------------------------------------------

    constructor(ProtocolAccessManager accessManager_) {
        if (address(accessManager_) == address(0)) revert ZeroAddress();
        accessManager = accessManager_;
    }

    modifier onlyTreasurer() {
        accessManager.requireRole(accessManager.TREASURER_ROLE(), msg.sender);
        _;
    }

    modifier onlyReporter() {
        accessManager.requireRole(accessManager.REPUTATION_REPORTER_ROLE(), msg.sender);
        _;
    }

    modifier solvent() {
        _;
        if (address(this).balance < totalOwed) revert Insolvent();
    }

    // --------------------------------------------------------------------
    // Registration
    // --------------------------------------------------------------------

    /**
     * @notice Name the wallet that referred you. Once, and never yourself.
     * @dev The caller registers their own referrer rather than a referrer
     *      claiming referees: a wallet should not be able to attach itself to
     *      someone else's account without that person acting.
     */
    function register(address referrer) external {
        if (referrer == address(0)) revert ZeroAddress();
        if (referrer == msg.sender) revert SelfReferral();
        if (referrerOf[msg.sender] != address(0)) revert AlreadyRegistered(msg.sender);

        uint8 referrerDepth = depthOf[referrer];
        if (referrerDepth >= MAX_DEPTH) revert ChainTooDeep(referrerDepth);

        // Walk up from the proposed referrer. If the caller is already an
        // ancestor, this registration would close a loop. The cap above makes
        // the walk both bounded and exhaustive.
        address cursor = referrer;
        for (uint8 i = 0; i <= MAX_DEPTH && cursor != address(0); i++) {
            if (cursor == msg.sender) revert CircularReferral(msg.sender, referrer);
            cursor = referrerOf[cursor];
        }

        referrerOf[msg.sender] = referrer;
        depthOf[msg.sender] = referrerDepth + 1;
        emit Registered(msg.sender, referrer, referrerDepth + 1);
    }

    // --------------------------------------------------------------------
    // Qualification
    // --------------------------------------------------------------------

    /**
     * @notice Record that `wallet` did the thing that earns its referrer a reward.
     * @dev Called by the protocol contract that witnessed it. One reward per
     *      referred wallet, whichever role qualified first: sec. 25 pays for
     *      bringing in a participant, not for each hat they wear.
     *
     *      Never reverts on the reward path. If the budget cannot cover it the
     *      qualification is still recorded and the shortfall is emitted, because
     *      the caller is a settlement contract and must not be made to fail over
     *      an empty referral purse.
     */
    function recordQualification(address wallet, Role role) external onlyReporter {
        if (wallet == address(0)) revert ZeroAddress();
        if (qualified[wallet]) revert AlreadyQualified(wallet);

        qualified[wallet] = true;
        address referrer = referrerOf[wallet];
        if (referrer == address(0)) {
            emit QualifiedWithoutReward(wallet, role, "no referrer");
            return;
        }

        uint256 amount = rewardAmount;
        if (amount == 0) {
            emit QualifiedWithoutReward(wallet, role, "reward not configured");
            return;
        }
        if (address(this).balance < totalOwed + amount) {
            emit QualifiedWithoutReward(wallet, role, "budget exhausted");
            return;
        }

        claimable[referrer] += amount;
        totalOwed += amount;
        emit Qualified(wallet, referrer, role, amount);
    }

    // --------------------------------------------------------------------
    // Money
    // --------------------------------------------------------------------

    /// @dev Permissionless, like the epoch budget: sponsors fund, roles spend.
    function fund() external payable solvent {
        if (msg.value == 0) revert ZeroAmount();
        emit Funded(msg.sender, msg.value);
    }

    function setRewardAmount(uint128 amount) external onlyTreasurer {
        rewardAmount = amount;
        emit RewardAmountSet(amount);
    }

    /// @notice Withdraw what referrals have earned you.
    function claim() external nonReentrant solvent {
        uint256 amount = claimable[msg.sender];
        if (amount == 0) revert NothingToClaim(msg.sender);

        claimable[msg.sender] = 0;
        totalOwed -= amount;

        emit Claimed(msg.sender, amount);
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert PayoutFailed(msg.sender, amount);
    }

    /// @notice MON held beyond what is owed to referrers.
    function surplus() external view returns (uint256) {
        uint256 balance = address(this).balance;
        return balance > totalOwed ? balance - totalOwed : 0;
    }

    receive() external payable {}
}
