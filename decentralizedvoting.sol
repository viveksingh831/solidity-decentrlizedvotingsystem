// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title NFT Marketplace
 * @dev A decentralized marketplace for buying and selling NFTs
 */
contract NFTMarketplace is ReentrancyGuard, Ownable {
    
    // Marketplace fee percentage (2.5%)
    uint256 public marketplaceFee = 250; // 250 basis points = 2.5%
    uint256 public constant MAX_FEE = 1000; // 10% max fee
    
    // Item counter for unique listing IDs
    uint256 private _itemIds;
    uint256 private _itemsSold;
    
    // Struct to represent a marketplace item
    struct MarketItem {
        uint256 itemId;
        address nftContract;
        uint256 tokenId;
        address payable seller;
        address payable owner;
        uint256 price;
        bool sold;
        uint256 listedAt;
    }
    
    // Mapping from item ID to market item
    mapping(uint256 => MarketItem) private idToMarketItem;
    
    // Events
    event MarketItemCreated(
        uint256 indexed itemId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        address owner,
        uint256 price
    );
    
    event MarketItemSold(
        uint256 indexed itemId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        address buyer,
        uint256 price
    );
    
    event MarketItemDelisted(
        uint256 indexed itemId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId
    );
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @dev Core Function 1: List an NFT for sale on the marketplace
     * @param nftContract Address of the NFT contract
     * @param tokenId ID of the NFT token
     * @param price Price in wei to sell the NFT for
     */
    function listItem(
        address nftContract,
        uint256 tokenId,
        uint256 price
    ) public nonReentrant {
        require(price > 0, "Price must be greater than 0");
        require(IERC721(nftContract).ownerOf(tokenId) == msg.sender, "You don't own this NFT");
        require(
            IERC721(nftContract).isApprovedForAll(msg.sender, address(this)) ||
            IERC721(nftContract).getApproved(tokenId) == address(this),
            "Marketplace not approved to transfer NFT"
        );
        
        _itemIds++;
        uint256 itemId = _itemIds;
        
        idToMarketItem[itemId] = MarketItem(
            itemId,
            nftContract,
            tokenId,
            payable(msg.sender),
            payable(address(0)), // No owner until sold
            price,
            false,
            block.timestamp
        );
        
        // Transfer NFT to marketplace contract
        IERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);
        
        emit MarketItemCreated(
            itemId,
            nftContract,
            tokenId,
            msg.sender,
            address(0),
            price
        );
    }
    
    /**
     * @dev Core Function 2: Purchase an NFT from the marketplace
     * @param itemId ID of the market item to purchase
     */
    function buyItem(uint256 itemId) public payable nonReentrant {
        MarketItem storage item = idToMarketItem[itemId];
        uint256 price = item.price;
        uint256 tokenId = item.tokenId;
        address nftContract = item.nftContract;
        
        require(msg.value == price, "Incorrect payment amount");
        require(!item.sold, "Item already sold");
        require(item.seller != address(0), "Item does not exist");
        require(msg.sender != item.seller, "Cannot buy your own item");
        
        // Calculate marketplace fee
        uint256 fee = (price * marketplaceFee) / 10000;
        uint256 sellerAmount = price - fee;
        
        // Update item status
        item.owner = payable(msg.sender);
        item.sold = true;
        _itemsSold++;
        
        // Transfer NFT to buyer
        IERC721(nftContract).transferFrom(address(this), msg.sender, tokenId);
        
        // Transfer payment to seller (minus fee)
        item.seller.transfer(sellerAmount);
        
        // Transfer fee to contract owner
        if (fee > 0) {
            payable(owner()).transfer(fee);
        }
        
        emit MarketItemSold(
            itemId,
            nftContract,
            tokenId,
            item.seller,
            msg.sender,
            price
        );
    }
    
    /**
     * @dev Core Function 3: Remove an NFT listing from the marketplace
     * @param itemId ID of the market item to delist
     */
    function delistItem(uint256 itemId) public nonReentrant {
        MarketItem storage item = idToMarketItem[itemId];
        
        require(item.seller == msg.sender, "Only seller can delist item");
        require(!item.sold, "Cannot delist sold item");
        require(item.seller != address(0), "Item does not exist");
        
        // Transfer NFT back to seller
        IERC721(item.nftContract).transferFrom(address(this), msg.sender, item.tokenId);
        
        emit MarketItemDelisted(itemId, msg.sender, item.nftContract, item.tokenId);
        
        // Remove item from marketplace
        delete idToMarketItem[itemId];
    }
    
    // View functions
    
    /**
     * @dev Get all unsold market items
     */
    function getAvailableItems() public view returns (MarketItem[] memory) {
        uint256 itemCount = _itemIds;
        uint256 unsoldItemCount = _itemIds - _itemsSold;
        uint256 currentIndex = 0;
        
        MarketItem[] memory items = new MarketItem[](unsoldItemCount);
        
        for (uint256 i = 0; i < itemCount; i++) {
            uint256 currentId = i + 1;
            MarketItem storage currentItem = idToMarketItem[currentId];
            
            if (!currentItem.sold && currentItem.seller != address(0)) {
                items[currentIndex] = currentItem;
                currentIndex++;
            }
        }
        
        return items;
    }
    
    /**
     * @dev Get items owned by the caller
     */
    function getMyItems() public view returns (MarketItem[] memory) {
        uint256 totalItemCount = _itemIds;
        uint256 itemCount = 0;
        uint256 currentIndex = 0;
        
        // Count items owned by caller
        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idToMarketItem[i + 1].owner == msg.sender) {
                itemCount++;
            }
        }
        
        MarketItem[] memory items = new MarketItem[](itemCount);
        
        for (uint256 i = 0; i < totalItemCount; i++) {
            uint256 currentId = i + 1;
            MarketItem storage currentItem = idToMarketItem[currentId];
            
            if (currentItem.owner == msg.sender) {
                items[currentIndex] = currentItem;
                currentIndex++;
            }
        }
        
        return items;
    }
    
    /**
     * @dev Get items listed by the caller
     */
    function getMyListedItems() public view returns (MarketItem[] memory) {
        uint256 totalItemCount = _itemIds;
        uint256 itemCount = 0;
        uint256 currentIndex = 0;
        
        // Count items listed by caller
        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idToMarketItem[i + 1].seller == msg.sender && !idToMarketItem[i + 1].sold) {
                itemCount++;
            }
        }
        
        MarketItem[] memory items = new MarketItem[](itemCount);
        
        for (uint256 i = 0; i < totalItemCount; i++) {
            uint256 currentId = i + 1;
            MarketItem storage currentItem = idToMarketItem[currentId];
            
            if (currentItem.seller == msg.sender && !currentItem.sold) {
                items[currentIndex] = currentItem;
                currentIndex++;
            }
        }
        
        return items;
    }
    
    /**
     * @dev Get a specific market item by ID
     */
    function getMarketItem(uint256 itemId) public view returns (MarketItem memory) {
        return idToMarketItem[itemId];
    }
    
    // Admin functions
    
    /**
     * @dev Update marketplace fee (only owner)
     */
    function updateMarketplaceFee(uint256 _feePercent) external onlyOwner {
        require(_feePercent <= MAX_FEE, "Fee cannot exceed maximum");
        marketplaceFee = _feePercent;
    }
    
    /**
     * @dev Withdraw accumulated fees (only owner)
     */
    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        payable(owner()).transfer(balance);
    }
    
    // Get marketplace statistics
    function getMarketplaceStats() external view returns (
        uint256 totalItems,
        uint256 totalSold,
        uint256 totalListed,
        uint256 currentFee
    ) {
        return (
            _itemIds,
            _itemsSold,
            _itemIds - _itemsSold,
            marketplaceFee
        );
    }
}
