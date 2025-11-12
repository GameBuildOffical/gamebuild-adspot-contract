// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC809} from "./interfaces/IERC809.sol";

/// @title AdSpotMarket - Buy, bid, pay, and claim rewards for AdSpotNFTs
/// @notice Marketplace supports fixed-price buy, simple English auction bidding, and rental revenue sharing
contract AdSpotMarket is Ownable, ReentrancyGuard {
    struct Sale {
        address seller;
        uint256 price; // fixed price in wei, 0 means not for sale
    }

    struct Auction {
        address seller;
        uint64 startTime;
        uint64 endTime;
        uint256 minBid;
        address highestBidder;
        uint256 highestBid;
        bool settled;
    }

    // token contract => tokenId => Sale
    mapping(address => mapping(uint256 => Sale)) public sales;

    // token contract => tokenId => Auction
    mapping(address => mapping(uint256 => Auction)) public auctions;

    // balances to claim by account (seller/renter revenue)
    mapping(address => uint256) public claimable;

    uint96 public feeBps; // protocol fee in basis points (1% = 100)
    address public feeReceiver;

    event List(address indexed nft, uint256 indexed tokenId, address indexed seller, uint256 price);
    event Unlist(address indexed nft, uint256 indexed tokenId);
    event Buy(address indexed nft, uint256 indexed tokenId, address indexed buyer, uint256 price);

    event AuctionCreated(address indexed nft, uint256 indexed tokenId, address seller, uint64 startTime, uint64 endTime, uint256 minBid);
    event Bid(address indexed nft, uint256 indexed tokenId, address bidder, uint256 amount);
    event AuctionSettled(address indexed nft, uint256 indexed tokenId, address winner, uint256 amount);

    event RentForwarded(address indexed nft, uint256 indexed tokenId, address payer, uint256 amount);
    event Claim(address indexed account, uint256 amount);

    error NotApproved();
    error InvalidParams();
    error NotSeller();
    error AuctionActive();
    error AuctionNotActive();
    error AuctionEnded();
    error AuctionNotEnded();
    error BidTooLow();

    constructor(address owner_, address feeReceiver_, uint96 feeBps_) Ownable(owner_) {
        feeReceiver = feeReceiver_;
        feeBps = feeBps_;
    }

    // Admin can update fee
    function setFee(address receiver, uint96 bps) external onlyOwner {
        require(bps <= 2_000, "fee too high"); // cap at 20%
        feeReceiver = receiver;
        feeBps = bps;
    }

    // Fixed price listing
    function list(address nft, uint256 tokenId, uint256 price) external {
        IERC721 erc = IERC721(nft);
        if (erc.ownerOf(tokenId) != msg.sender) revert NotSeller();
        if (!erc.isApprovedForAll(msg.sender, address(this)) && erc.getApproved(tokenId) != address(this)) revert NotApproved();
        if (price == 0) revert InvalidParams();
        sales[nft][tokenId] = Sale({seller: msg.sender, price: price});
        emit List(nft, tokenId, msg.sender, price);
    }

    function unlist(address nft, uint256 tokenId) external {
        Sale memory s = sales[nft][tokenId];
        if (s.seller != msg.sender) revert NotSeller();
        delete sales[nft][tokenId];
        emit Unlist(nft, tokenId);
    }

    // Buy now
    function buy(address nft, uint256 tokenId) external payable nonReentrant {
        Sale memory s = sales[nft][tokenId];
        if (s.price == 0) revert InvalidParams();
        if (msg.value < s.price) revert InvalidParams();

        delete sales[nft][tokenId];

        // protocol fee
        uint256 fee = (msg.value * feeBps) / 10_000;
        uint256 sellerProceeds = msg.value - fee;
        claimable[feeReceiver] += fee;
        claimable[s.seller] += sellerProceeds;

        IERC721(nft).safeTransferFrom(s.seller, msg.sender, tokenId);
        emit Buy(nft, tokenId, msg.sender, msg.value);
    }

    // Auction setup
    function createAuction(address nft, uint256 tokenId, uint64 startTime, uint64 endTime, uint256 minBid) external {
        IERC721 erc = IERC721(nft);
        if (erc.ownerOf(tokenId) != msg.sender) revert NotSeller();
        if (!erc.isApprovedForAll(msg.sender, address(this)) && erc.getApproved(tokenId) != address(this)) revert NotApproved();
        if (startTime >= endTime || endTime <= block.timestamp) revert InvalidParams();
        if (auctions[nft][tokenId].startTime != 0 && !auctions[nft][tokenId].settled) revert AuctionActive();

        auctions[nft][tokenId] = Auction({
            seller: msg.sender,
            startTime: startTime,
            endTime: endTime,
            minBid: minBid,
            highestBidder: address(0),
            highestBid: 0,
            settled: false
        });
        emit AuctionCreated(nft, tokenId, msg.sender, startTime, endTime, minBid);
    }

    function bid(address nft, uint256 tokenId) external payable nonReentrant {
        Auction storage a = auctions[nft][tokenId];
        if (a.startTime == 0 || a.settled) revert AuctionNotActive();
        if (block.timestamp < a.startTime) revert AuctionNotActive();
        if (block.timestamp >= a.endTime) revert AuctionEnded();

        uint256 minReq = a.highestBid == 0 ? a.minBid : a.highestBid + ((a.highestBid * 5) / 100); // +5%
        if (msg.value < minReq) revert BidTooLow();

        // refund previous
        if (a.highestBidder != address(0)) {
            claimable[a.highestBidder] += a.highestBid;
        }

        a.highestBidder = msg.sender;
        a.highestBid = msg.value;
        emit Bid(nft, tokenId, msg.sender, msg.value);
    }

    function settle(address nft, uint256 tokenId) external nonReentrant {
        Auction storage a = auctions[nft][tokenId];
        if (a.startTime == 0 || a.settled) revert AuctionNotActive();
        if (block.timestamp < a.endTime) revert AuctionNotEnded();

        a.settled = true;
        if (a.highestBidder != address(0)) {
            uint256 fee = (a.highestBid * feeBps) / 10_000;
            uint256 sellerProceeds = a.highestBid - fee;
            claimable[feeReceiver] += fee;
            claimable[a.seller] += sellerProceeds;
            IERC721(nft).safeTransferFrom(a.seller, a.highestBidder, tokenId);
        }
        emit AuctionSettled(nft, tokenId, a.highestBidder, a.highestBid);
    }

    // Rental payment helper: forwards payment to protocol escrow balances respecting fee
    // Note: The NFT contract may call this during rent(), or renter can call prior to rent()
    function payRent(address nft, uint256 tokenId) external payable nonReentrant {
        // We don't validate price here; NFT contract enforces on rent(). This function only accounts fees.
        uint256 fee = (msg.value * feeBps) / 10_000;
        claimable[feeReceiver] += fee;
        address ownerOfToken = IERC721(nft).ownerOf(tokenId);
        claimable[ownerOfToken] += (msg.value - fee);
        emit RentForwarded(nft, tokenId, msg.sender, msg.value);
    }

    // Claim accumulated balances
    function claim() external nonReentrant {
        uint256 amount = claimable[msg.sender];
        require(amount > 0, "nothing to claim");
        claimable[msg.sender] = 0;
        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        require(ok, "transfer failed");
        emit Claim(msg.sender, amount);
    }

    receive() external payable {
        // accept ETH
    }
}
