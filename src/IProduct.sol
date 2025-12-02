// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IProductNft {
    function mintProductNft(address to, string memory tokenUri) external returns (uint256);
}

interface ISupplyChain {
    function buildMetadata(uint256 productId) external view returns (string memory);
}
