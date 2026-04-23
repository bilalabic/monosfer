// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract ReputationBadge {
    enum BadgeType {
        FirstDelivery,
        WeeklyChampion,
        MonthlyChampion,
        PerfectRating,
        RegionLord
    }

    string public name = "Delivera Reputation Badge";
    string public symbol = "DRB";
    address public owner;
    address public minter;
    uint256 public nextTokenId = 1;

    mapping(uint256 => address) private _ownerOf;
    mapping(address => uint256) public balanceOf;
    mapping(uint256 => BadgeType) public badgeTypeOf;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event MinterUpdated(address indexed newMinter);
    event BadgeMinted(address indexed user, uint256 indexed tokenId, BadgeType badgeType);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyMinter() {
        require(msg.sender == minter, "Not minter");
        _;
    }

    constructor(address initialOwner) {
        require(initialOwner != address(0), "Owner zero");
        owner = initialOwner;
    }

    function setMinter(address newMinter) external onlyOwner {
        require(newMinter != address(0), "Minter zero");
        minter = newMinter;
        emit MinterUpdated(newMinter);
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        address tokenOwner = _ownerOf[tokenId];
        require(tokenOwner != address(0), "Not minted");
        return tokenOwner;
    }

    function mint(address to, BadgeType badgeType) external onlyMinter returns (uint256 tokenId) {
        require(to != address(0), "To zero");
        tokenId = nextTokenId++;
        _ownerOf[tokenId] = to;
        balanceOf[to] += 1;
        badgeTypeOf[tokenId] = badgeType;

        emit Transfer(address(0), to, tokenId);
        emit BadgeMinted(to, tokenId, badgeType);
    }

    // Soulbound: transfer islemleri bilerek devre disi.
    function transferFrom(address, address, uint256) external pure {
        revert("Soulbound");
    }
}
