// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProtocolAccessManager} from "../../src/v1/access/ProtocolAccessManager.sol";
import {FallbackCommittee} from "../../src/v1/dispute/FallbackCommittee.sol";

/// @dev A contract wallet that approves exactly the digests it is told to.
contract ApprovingWallet {
    mapping(bytes32 => bool) public approved;

    function approve(bytes32 digest) external {
        approved[digest] = true;
    }

    function isValidSignature(bytes32 digest, bytes calldata) external view returns (bytes4) {
        return approved[digest] ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
    }
}

/**
 * @notice The sec. 31 fallback, on its own terms.
 * @dev `DisputeCourt.t.sol` proves what the committee can do *to a dispute*.
 *      This suite proves what the committee contract itself will and will not
 *      accept, because `requireDecision` is a public entry point with its own
 *      guarantees and the court's phase machine must not be the only thing
 *      standing between a stale signature and a ruling.
 *
 *      The court is played by this test contract, which holds
 *      `DISPUTE_COURT_ROLE` — that is what the committee checks, and it is the
 *      honest way to reach the checks the court's own state machine hides.
 */
contract FallbackCommitteeTest is Test {
    ProtocolAccessManager internal manager;
    FallbackCommittee internal committee;

    address internal admin = address(0xA11CE);
    address internal signerAdmin = address(0x5164E);
    address internal outsider = address(0xBAD);

    uint256 internal constant SAFE_KEY = 0x5AFE;
    address internal safeSigner;

    bytes32 internal constant DECISION_TYPEHASH =
        keccak256("FallbackDecision(uint256 disputeId,uint8 round,uint8 ruling,uint64 expiresAt)");
    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    function setUp() public {
        safeSigner = vm.addr(SAFE_KEY);
        manager = new ProtocolAccessManager(3 days, admin);
        committee = new FallbackCommittee(manager, safeSigner);

        vm.startPrank(admin);
        manager.grantRole(manager.SIGNER_ADMIN_ROLE(), signerAdmin);
        // This test contract stands in for the court.
        manager.grantRole(manager.DISPUTE_COURT_ROLE(), address(this));
        vm.stopPrank();
    }

    // ------------------------------------------------------------ helpers

    function _decision(uint256 disputeId, uint8 round, uint8 ruling)
        internal
        view
        returns (FallbackCommittee.Decision memory)
    {
        return FallbackCommittee.Decision({
            disputeId: disputeId, round: round, ruling: ruling, expiresAt: uint64(block.timestamp + 1 days)
        });
    }

    function _sign(FallbackCommittee.Decision memory decision, uint256 key) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, committee.hashDecision(decision));
        return abi.encodePacked(r, s, v);
    }

    // ------------------------------------------------- who may consume one

    /**
     * @dev Burning a decision is a state change. If anyone could burn one, a
     *      bystander could spend the signature the court was about to use and
     *      leave the case stuck with a committee that has already signed.
     */
    function test_OnlyTheCourtMayConsumeADecision() public {
        FallbackCommittee.Decision memory decision = _decision(1, 1, 5);
        bytes memory sig = _sign(decision, SAFE_KEY);

        vm.expectRevert();
        vm.prank(outsider);
        committee.requireDecision(1, 1, decision, sig);
    }

    /**
     * @dev The check the court's own phase machine hides: once a dispute is
     *      settled it will not accept a second decision anyway, so nothing in
     *      that suite can reach this. Reached here directly, because a public
     *      entry point has to hold on its own.
     */
    function test_ADecisionIsSingleUse() public {
        FallbackCommittee.Decision memory decision = _decision(7, 2, 3);
        bytes memory sig = _sign(decision, SAFE_KEY);

        uint8 first = committee.requireDecision(7, 2, decision, sig);
        assertEq(first, 3, "accepted once");

        bytes32 digest = committee.hashDecision(decision);
        assertTrue(committee.used(digest), "and burned");

        vm.expectRevert(abi.encodeWithSelector(FallbackCommittee.DecisionAlreadyUsed.selector, digest));
        committee.requireDecision(7, 2, decision, sig);
    }

    // ------------------------------------------- sec. 31: bounded codes only

    /**
     * @dev The one sentence this contract exists to make true. Codes 1..6 are
     *      the sec. 30 outcomes; 0 is `None` and 7 is nothing at all.
     */
    function test_OnlyTheSixRulingCodesAreAccepted() public {
        for (uint8 code = 1; code <= 6; code++) {
            FallbackCommittee.Decision memory ok = _decision(code, 1, code);
            assertEq(committee.requireDecision(code, 1, ok, _sign(ok, SAFE_KEY)), code);
        }

        uint8[2] memory bad = [uint8(0), uint8(7)];
        for (uint256 i = 0; i < bad.length; i++) {
            FallbackCommittee.Decision memory decision = _decision(100 + i, 1, bad[i]);
            bytes memory sig = _sign(decision, SAFE_KEY);
            vm.expectRevert(abi.encodeWithSelector(FallbackCommittee.RulingNotAllowed.selector, bad[i]));
            committee.requireDecision(100 + i, 1, decision, sig);
        }
    }

    /// @dev Whatever a committee signs, it is a number in range and nothing else.
    function testFuzz_NothingOutsideTheRangeIsEverAccepted(uint8 code) public {
        vm.assume(code < committee.MIN_RULING() || code > committee.MAX_RULING());

        FallbackCommittee.Decision memory decision = _decision(9, 1, code);
        bytes memory sig = _sign(decision, SAFE_KEY);

        vm.expectRevert(abi.encodeWithSelector(FallbackCommittee.RulingNotAllowed.selector, code));
        committee.requireDecision(9, 1, decision, sig);
    }

    // ----------------------------------------------------- what binds a decision

    function test_ADecisionIsBoundToItsDispute() public {
        FallbackCommittee.Decision memory decision = _decision(1, 1, 5);
        bytes memory sig = _sign(decision, SAFE_KEY);

        vm.expectRevert(abi.encodeWithSelector(FallbackCommittee.WrongDispute.selector, uint256(2), uint256(1)));
        committee.requireDecision(2, 1, decision, sig);
    }

    function test_ADecisionIsBoundToItsRound() public {
        FallbackCommittee.Decision memory decision = _decision(1, 1, 5);
        bytes memory sig = _sign(decision, SAFE_KEY);

        vm.expectRevert(abi.encodeWithSelector(FallbackCommittee.WrongRound.selector, uint8(3), uint8(1)));
        committee.requireDecision(1, 3, decision, sig);
    }

    function test_ADecisionGoesStale() public {
        FallbackCommittee.Decision memory decision = _decision(1, 1, 5);
        bytes memory sig = _sign(decision, SAFE_KEY);

        vm.warp(decision.expiresAt + 1);
        vm.expectRevert(abi.encodeWithSelector(FallbackCommittee.DecisionExpired.selector, decision.expiresAt));
        committee.requireDecision(1, 1, decision, sig);
    }

    /// @dev The last valid second is accepted, the one after it is not.
    function test_TheExpiryEdgeIsInclusive() public {
        FallbackCommittee.Decision memory decision = _decision(1, 1, 5);
        bytes memory sig = _sign(decision, SAFE_KEY);

        vm.warp(decision.expiresAt);
        assertEq(committee.requireDecision(1, 1, decision, sig), 5, "the final second still counts");
    }

    function test_SomebodyElsesSignatureIsRefused() public {
        FallbackCommittee.Decision memory decision = _decision(1, 1, 5);
        bytes memory forged = _sign(decision, uint256(0xC0FFEE));

        bytes32 digest = committee.hashDecision(decision);
        vm.expectRevert(abi.encodeWithSelector(FallbackCommittee.DecisionSignatureInvalid.selector, digest));
        committee.requireDecision(1, 1, decision, forged);
    }

    /**
     * @dev Derived here from the type string rather than by asking the contract.
     *      Signing with the same function the contract verifies against would be
     *      self-consistent even if the type string were wrong.
     */
    function test_DigestMatchesAnIndependentDerivation() public view {
        FallbackCommittee.Decision memory decision = _decision(42, 2, 4);

        bytes32 domain = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("MonosferFallbackCommittee")),
                keccak256(bytes("1")),
                block.chainid,
                address(committee)
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(DECISION_TYPEHASH, decision.disputeId, decision.round, decision.ruling, decision.expiresAt)
        );
        bytes32 expected = keccak256(abi.encodePacked(hex"1901", domain, structHash));

        assertEq(committee.hashDecision(decision), expected);
        assertEq(committee.domainSeparator(), domain);
    }

    /// @dev A signature for this deployment is worthless against another one.
    function test_TheDomainBindsThisDeployment() public {
        FallbackCommittee other = new FallbackCommittee(manager, safeSigner);
        assertTrue(committee.domainSeparator() != other.domainSeparator(), "two deployments, two domains");
    }

    // ---------------------------------------------------------- the Safe itself

    /// @dev sec. 31's real shape: a Safe answering through ERC-1271.
    function test_AContractWalletIsAccepted() public {
        ApprovingWallet wallet = new ApprovingWallet();
        vm.prank(signerAdmin);
        committee.setSafe(address(wallet));

        FallbackCommittee.Decision memory decision = _decision(1, 1, 6);
        wallet.approve(committee.hashDecision(decision));

        assertEq(committee.requireDecision(1, 1, decision, hex""), 6, "the Safe said yes");
    }

    function test_AContractWalletThatSaysNoIsRefused() public {
        ApprovingWallet wallet = new ApprovingWallet();
        vm.prank(signerAdmin);
        committee.setSafe(address(wallet));

        FallbackCommittee.Decision memory decision = _decision(1, 1, 6);
        bytes32 digest = committee.hashDecision(decision);

        vm.expectRevert(abi.encodeWithSelector(FallbackCommittee.DecisionSignatureInvalid.selector, digest));
        committee.requireDecision(1, 1, decision, hex"");
    }

    /// @dev Rotating the committee retires the old one's signatures immediately.
    function test_RotatingTheSafeRetiresTheOldSignatures() public {
        FallbackCommittee.Decision memory decision = _decision(1, 1, 5);
        bytes memory sig = _sign(decision, SAFE_KEY);

        address replacement = vm.addr(0xBEEF);
        vm.prank(signerAdmin);
        committee.setSafe(replacement);

        bytes32 digest = committee.hashDecision(decision);
        vm.expectRevert(abi.encodeWithSelector(FallbackCommittee.DecisionSignatureInvalid.selector, digest));
        committee.requireDecision(1, 1, decision, sig);
    }

    function test_OnlyTheSignerAdminMayRotateTheSafe() public {
        vm.expectRevert();
        vm.prank(outsider);
        committee.setSafe(address(0xFEED));

        vm.expectRevert(FallbackCommittee.ZeroAddress.selector);
        vm.prank(signerAdmin);
        committee.setSafe(address(0));
    }

    /**
     * @dev A deployment may ship before its committee exists. Until it is
     *      pointed somewhere, the fallback refuses everyone rather than
     *      accepting anyone — `address(0)` must never be a signer that passes.
     */
    function test_AnUnconfiguredCommitteeAcceptsNobody() public {
        FallbackCommittee unset = new FallbackCommittee(manager, address(0));
        assertEq(unset.safe(), address(0));

        FallbackCommittee.Decision memory decision = _decision(1, 1, 5);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SAFE_KEY, unset.hashDecision(decision));

        vm.expectRevert(FallbackCommittee.CommitteeNotConfigured.selector);
        unset.requireDecision(1, 1, decision, abi.encodePacked(r, s, v));
    }
}
