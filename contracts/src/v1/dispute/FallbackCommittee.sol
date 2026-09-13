// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import {ProtocolAccessManager} from "../access/ProtocolAccessManager.sol";

/**
 * @title FallbackCommittee
 * @notice sec. 31's last-resort liveness signer: a 3-of-5 Safe that may pick one
 *         bounded ruling code and nothing else.
 * @dev Baseline refs: sec. 31 (the fallback itself), sec. 30 (the six outcomes a
 *      ruling may be), sec. 45 (governance separation).
 *
 *      ## What this contract is for, and what it deliberately is not
 *
 *      A jury can fail to produce an answer: the randomness provider goes quiet,
 *      nobody reveals, or a panel cannot be seated at all. The money is escrowed
 *      either way, so a protocol with no answer for that case is a protocol that
 *      can strand funds. sec. 31 gives one: a multisig that can end the case.
 *
 *      That power is real, so its shape matters more than its existence. This
 *      contract exists to make one sentence true — **the committee may only
 *      choose from the same six outcomes a jury could have chosen.** It cannot
 *      name a recipient, cannot set an amount, cannot reach the vault, and
 *      cannot touch a dispute that is still running. It votes, in the same
 *      vocabulary as the jury it is standing in for, and the settlement path it
 *      feeds is the one the jury would have fed.
 *
 *      The 3-of-5 threshold is not implemented here. It lives inside the Safe,
 *      which is what a Safe is for; this contract sees one address and one
 *      ERC-1271 signature, and asks the Safe whether that signature is good. So
 *      "3-of-5" is a property of the account governance points at, and rotating
 *      the committee means pointing at a different Safe.
 *
 *      ## Why the signature is typed data
 *
 *      A committee member signing a raw hash is signing something they cannot
 *      read. EIP-712 means their wallet shows the dispute, the round and the
 *      ruling, which is the difference between approving a decision and
 *      approving a blob. The domain binds the chain and this contract, and
 *      `expiresAt` stops a signature gathered for one moment from being held and
 *      used much later.
 */
contract FallbackCommittee {
    // --------------------------------------------------------------------
    // Typed data
    // --------------------------------------------------------------------

    /**
     * @param disputeId The case being ended.
     * @param round     The round that failed, so a signature for one failed
     *                  round cannot end a different one later.
     * @param ruling    One of the sec. 30 codes. Never a payment instruction.
     * @param expiresAt Last timestamp at which the signature may be used.
     */
    struct Decision {
        uint256 disputeId;
        uint8 round;
        uint8 ruling;
        uint64 expiresAt;
    }

    bytes32 internal constant DECISION_TYPEHASH =
        keccak256("FallbackDecision(uint256 disputeId,uint8 round,uint8 ruling,uint64 expiresAt)");

    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    bytes32 internal immutable _domainSeparator;
    uint256 private immutable _cachedChainId;

    // --------------------------------------------------------------------
    // Storage
    // --------------------------------------------------------------------

    ProtocolAccessManager public immutable accessManager;

    /// @notice The Safe whose ERC-1271 signature ends a failed case (sec. 31).
    address public safe;

    /// @notice Consumed decisions, so one signature ends one case once.
    mapping(bytes32 => bool) public used;

    // --------------------------------------------------------------------
    // Events and errors
    // --------------------------------------------------------------------

    event SafeChanged(address indexed previous, address indexed next);
    event DecisionConsumed(uint256 indexed disputeId, uint8 round, uint8 ruling);

    error ZeroAddress();
    error CommitteeNotConfigured();
    error DecisionExpired(uint64 expiresAt);
    error DecisionAlreadyUsed(bytes32 digest);
    error DecisionSignatureInvalid(bytes32 digest);
    error WrongDispute(uint256 expected, uint256 actual);
    error WrongRound(uint8 expected, uint8 actual);
    error RulingNotAllowed(uint8 ruling);

    // --------------------------------------------------------------------
    // Wiring
    // --------------------------------------------------------------------

    /// @notice The lowest and highest sec. 30 ruling codes this will accept.
    /// @dev Mirrors `DisputeCourt.Ruling`: 0 is `None` and is refused, 6 is
    ///      `Refuse` and is the last real outcome. Held as plain numbers rather
    ///      than by importing the enum, because importing the court here would
    ///      make the two contracts mutually dependent at construction.
    uint8 public constant MIN_RULING = 1;
    uint8 public constant MAX_RULING = 6;

    constructor(ProtocolAccessManager accessManager_, address safe_) {
        if (address(accessManager_) == address(0)) revert ZeroAddress();

        accessManager = accessManager_;
        _cachedChainId = block.chainid;
        _domainSeparator = _buildDomainSeparator();

        // A deployment may start without a committee and point at one later;
        // until it does, `requireDecision` refuses rather than accepting
        // anybody's signature.
        if (safe_ != address(0)) {
            safe = safe_;
            emit SafeChanged(address(0), safe_);
        }
    }

    // --------------------------------------------------------------------
    // Governance
    // --------------------------------------------------------------------

    /**
     * @notice Point the fallback at a different Safe.
     * @dev Immediate rather than timelocked, and under `SIGNER_ADMIN_ROLE` for
     *      the same reason the quote and attestation signers are: a committee
     *      whose keys are compromised has to be replaceable now, and a two-day
     *      wait would be two days of a hostile signer holding the fallback.
     *      The power this grants is bounded by what the committee can do at all,
     *      which is to pick one of six outcomes.
     */
    function setSafe(address next) external {
        accessManager.requireRole(accessManager.SIGNER_ADMIN_ROLE(), msg.sender);
        if (next == address(0)) revert ZeroAddress();

        address previous = safe;
        safe = next;
        emit SafeChanged(previous, next);
    }

    // --------------------------------------------------------------------
    // Verification
    // --------------------------------------------------------------------

    /**
     * @notice Validate and burn a committee decision.
     * @dev Every check is separate and reverts with its own error, so a caller
     *      learns which rule they broke rather than being told "invalid".
     * @param disputeId The dispute the court is trying to end.
     * @param round     The round it failed on.
     * @param decision  What the committee signed.
     * @param signature The Safe's ERC-1271 signature over `hashDecision`.
     * @return ruling The accepted ruling code.
     */
    function requireDecision(uint256 disputeId, uint8 round, Decision calldata decision, bytes calldata signature)
        external
        returns (uint8 ruling)
    {
        // Only the court may burn a decision: burning is a state change, and a
        // decision anyone could burn could be burned out from under the call
        // that was about to use it.
        accessManager.requireRole(accessManager.DISPUTE_COURT_ROLE(), msg.sender);

        address signer = safe;
        if (signer == address(0)) revert CommitteeNotConfigured();

        if (decision.disputeId != disputeId) revert WrongDispute(disputeId, decision.disputeId);
        if (decision.round != round) revert WrongRound(round, decision.round);
        // The whole point of sec. 31: bounded codes only, never a transfer.
        if (decision.ruling < MIN_RULING || decision.ruling > MAX_RULING) revert RulingNotAllowed(decision.ruling);
        if (block.timestamp > decision.expiresAt) revert DecisionExpired(decision.expiresAt);

        bytes32 digest = hashDecision(decision);
        if (used[digest]) revert DecisionAlreadyUsed(digest);
        if (!SignatureChecker.isValidSignatureNow(signer, digest, signature)) {
            revert DecisionSignatureInvalid(digest);
        }

        used[digest] = true;
        emit DecisionConsumed(disputeId, round, decision.ruling);
        return decision.ruling;
    }

    /// @notice The EIP-712 digest a committee member's wallet is asked to sign.
    function hashDecision(Decision calldata decision) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(DECISION_TYPEHASH, decision.disputeId, decision.round, decision.ruling, decision.expiresAt)
        );
        return keccak256(abi.encodePacked(hex"1901", domainSeparator(), structHash));
    }

    /// @notice The EIP-712 domain, rebuilt if the chain forked under us.
    function domainSeparator() public view returns (bytes32) {
        return block.chainid == _cachedChainId ? _domainSeparator : _buildDomainSeparator();
    }

    function _buildDomainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("MonosferFallbackCommittee")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }
}
