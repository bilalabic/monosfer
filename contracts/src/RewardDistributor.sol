// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract RewardDistributor {
    address public owner;
    address public immutable rewardToken;

    mapping(uint256 => bytes32) public merkleRoots;
    mapping(uint256 => mapping(address => bool)) public claimed;

    event MerkleRootSet(uint256 indexed periodId, bytes32 root);
    event RewardClaimed(uint256 indexed periodId, address indexed user, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(address initialOwner, address token) {
        require(initialOwner != address(0), "Owner zero");
        require(token != address(0), "Token zero");
        owner = initialOwner;
        rewardToken = token;
    }

    function setMerkleRoot(uint256 periodId, bytes32 root) external onlyOwner {
        require(root != bytes32(0), "Root zero");
        merkleRoots[periodId] = root;
        emit MerkleRootSet(periodId, root);
    }

    function claimReward(uint256 periodId, uint256 amount, bytes32[] calldata proof) external {
        require(!claimed[periodId][msg.sender], "Already claimed");
        bytes32 root = merkleRoots[periodId];
        require(root != bytes32(0), "Root not set");

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender, amount))));
        require(_verifyProof(proof, root, leaf), "Invalid proof");

        claimed[periodId][msg.sender] = true;
        (bool ok, bytes memory data) =
            rewardToken.call(abi.encodeWithSignature("transfer(address,uint256)", msg.sender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "Token transfer failed");

        emit RewardClaimed(periodId, msg.sender, amount);
    }

    function _verifyProof(bytes32[] calldata proof, bytes32 root, bytes32 leaf) internal pure returns (bool) {
        bytes32 computedHash = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            if (computedHash <= proofElement) {
                computedHash = keccak256(bytes.concat(computedHash, proofElement));
            } else {
                computedHash = keccak256(bytes.concat(proofElement, computedHash));
            }
        }
        return computedHash == root;
    }
}
