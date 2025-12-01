// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import "src/IProduct.sol"; // interface

contract ProductNft is ERC721 {
    // Stores SupplyChain contract reference
    ISupplyChain public supplyChain;

    // Counter for NFT ids
    uint256 private s_tokenCounter;

    // Optional stored metadata
    mapping(uint256 => string) private s_tokenIdToUri;

    // Save supply chain contract reference
    constructor(address _supplyChain) ERC721("SupplyChainProduct", "SCP") {
        require(_supplyChain != address(0), "supplyChain-required");
        supplyChain = ISupplyChain(_supplyChain);
        s_tokenCounter = 0;
    }

    // Mints a product NFT
    function mintProductNft(address to, string memory tokenUri) external returns (uint256) {
        uint256 newId = s_tokenCounter;

        s_tokenIdToUri[newId] = tokenUri;
        _safeMint(to, newId);

        s_tokenCounter++;
        return newId;
    }

    // Returns metadata (stored OR generated)
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        // If explicit metadata exists, return it
        if (bytes(s_tokenIdToUri[tokenId]).length != 0) {
            return s_tokenIdToUri[tokenId];
        }

        // Otherwise request JSON from SupplyChain
        string memory json = supplyChain.buildMetadata(tokenId);

        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));
    }
}
