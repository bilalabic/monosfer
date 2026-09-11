// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title IERC5192
 * @notice Minimal Soulbound Token interface (EIP-5192).
 * @dev Not shipped by OpenZeppelin 5.x, so it is declared here rather than
 *      approximated. Wallets and explorers key off this interface id to render a
 *      token as non-transferable; a badge that merely reverts on transfer without
 *      announcing itself looks like a broken NFT instead of a soulbound one.
 */
interface IERC5192 {
    /// @notice Emitted when a token is locked, i.e. becomes non-transferable.
    event Locked(uint256 tokenId);

    /// @notice Emitted when a token is unlocked. MONOSFER badges never unlock.
    event Unlocked(uint256 tokenId);

    /// @notice Whether `tokenId` is locked. Reverts if the token does not exist.
    function locked(uint256 tokenId) external view returns (bool);
}
