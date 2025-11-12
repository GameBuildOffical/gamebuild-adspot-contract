// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC809} from "./interfaces/IERC809.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title AdSpotNFT - Represents an advertising spot as an ERC721 + rentable via ERC-809 draft
/// @notice Each token can be rented for a time-based usage (e.g., displaying an ad)
contract AdSpotNFT is ERC721URIStorage, Ownable, IERC809 {
    struct RentalInfo {
        address user; // current renter
        uint64 expires; // unix timestamp when rental ends
        uint256 pricePerSecond; // configured price per second
    }

    uint256 private _nextId = 1;
    mapping(uint256 => RentalInfo) private _rentalInfo;

    error NotOwner();
    error InvalidDuration();
    // error InsufficientPayment(uint256 required, uint256 sent); // deprecated: payment handled externally via marketplace escrow

    constructor(address initialOwner) ERC721("GameBuild Ad Spot", "GBADSPOT") Ownable(initialOwner) {}

    function supportsInterface(bytes4 interfaceId) public view override(ERC721URIStorage, IERC165) returns (bool) {
        return interfaceId == type(IERC809).interfaceId || super.supportsInterface(interfaceId);
    }

    // Mint new ad spot NFT to owner
    function createSpot(string memory uri) external onlyOwner returns (uint256 tokenId) {
        tokenId = _nextId++;
        _safeMint(owner(), tokenId);
        _setTokenURI(tokenId, uri);
    }

    // IERC809
    function userOf(uint256 tokenId) external view returns (address) {
        RentalInfo memory info = _rentalInfo[tokenId];
        if (block.timestamp > info.expires) return address(0);
        return info.user;
    }

    function userExpires(uint256 tokenId) external view returns (uint256) {
        return _rentalInfo[tokenId].expires;
    }

    function pricePerSecond(uint256 tokenId) external view returns (uint256) {
        return _rentalInfo[tokenId].pricePerSecond;
    }

    function rent(uint256 tokenId, uint64 duration) external payable {
        // Pricing & payment are expected to be handled by external marketplace (e.g., AdSpotMarket.payRent)
        if (duration == 0) revert InvalidDuration();
        RentalInfo storage info = _rentalInfo[tokenId];
        uint256 start = block.timestamp > info.expires ? block.timestamp : info.expires; // queue after current expiry
        uint256 end = start + duration;
        info.user = msg.sender;
        info.expires = uint64(end);
        emit Rent(tokenId, msg.sender, uint64(start), uint64(end), msg.value);
    }

    function setPricePerSecond(uint256 tokenId, uint256 price) external {
        if (msg.sender != ownerOf(tokenId) && msg.sender != owner()) revert NotOwner();
        _rentalInfo[tokenId].pricePerSecond = price;
    }

    // Clear rental on transfer if expired; if active we keep user until expiry (optional behavior)
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = super._update(to, tokenId, auth);
        RentalInfo storage info = _rentalInfo[tokenId];
        if (block.timestamp > info.expires) {
            if (info.user != address(0)) {
                info.user = address(0);
                info.expires = 0;
                emit ClearUser(tokenId);
            }
        }
        return from;
    }
}
