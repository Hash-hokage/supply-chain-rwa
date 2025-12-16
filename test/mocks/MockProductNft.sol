//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

interface IProductNft {
    function mintProductNft(address to, string memory tokenURI) external returns (uint256);
}

contract MockProductNft is ERC721, IProductNft {
    uint256 public tokenCounter;

    constructor() ERC721("Mock Product", "MPROD") {}

    function mintProductNft(address to, string memory tokenURI) external returns (uint256) {
        uint256 newItemId = tokenCounter;
        _safeMint(to, newItemId);
        tokenCounter++;
        return newItemId;
    }
}
