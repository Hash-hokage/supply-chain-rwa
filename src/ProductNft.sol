// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract ProductNft is ERC721 {
    uint256 private s_tokenCounter;
    mapping(uint256 => string) private s_tokenIdToUri;
    address public supplyChain;

    constructor() ERC721("SupplyChainProduct", "SCP") {
        s_tokenCounter = 0;
    }

    // returns the new productId
    function mintProductNft(address to, string memory tokenUri) external returns (uint256) {
        uint256 newProductId = s_tokenCounter;
        s_tokenIdToUri[newProductId] = tokenUri;

        _safeMint(to, newProductId);

        s_tokenCounter++;

        return newProductId;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return s_tokenIdToUri[tokenId];
    }
}
