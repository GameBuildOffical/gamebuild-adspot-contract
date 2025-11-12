// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title ERC-809 Rentable NFT (Draft interface)
/// @notice Simplified interface to express time-based renting of an NFT.
/// @dev This interface aims to be compatible with a time-slot rental model.
interface IERC809 is IERC165 {
    /// Emitted when a rental is created or extended
    event Rent(
        uint256 indexed tokenId,
        address indexed renter,
        uint64 startTime,
        uint64 endTime,
        uint256 paid
    );

    /// Emitted when a rental is cleared (upon transfer or manual admin clear)
    event ClearUser(uint256 indexed tokenId);

    /// Return the current user (renter) and expiration timestamp for a token
    function userOf(uint256 tokenId) external view returns (address);

    function userExpires(uint256 tokenId) external view returns (uint256);

    /// Price per second for renting this token (set by owner/controller)
    function pricePerSecond(uint256 tokenId) external view returns (uint256);

    /// Request to rent a token starting at the earliest available time for a given duration (seconds).
    /// Implementations should queue rentals after the current expiry if busy.
    function rent(uint256 tokenId, uint64 duration) external payable;

    /// Set the price per second for rentals. Only callable by the token owner or authorized account.
    function setPricePerSecond(uint256 tokenId, uint256 price) external;
}
