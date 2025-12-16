// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol"; // Security Layer
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {ISupplyChain} from "src/IProduct.sol";

contract ProductNft is ERC721, Ownable {
    ISupplyChain public supplyChain;
    uint256 private s_tokenCounter;
    mapping(uint256 => string) private s_tokenIdToUri;

    event ProductMinted(uint256 indexed tokenId, address indexed to);

    constructor() ERC721("SupplyChainProduct", "SCP") Ownable(msg.sender) {}

    function setSupplyChain(address _supplyChain) external onlyOwner {
        require(address(supplyChain) == address(0), "Already set");
        supplyChain = ISupplyChain(_supplyChain);
        _transferOwnership(_supplyChain);
    }

    modifier onlySupplyChain() {
        require(msg.sender == address(supplyChain), "Only SupplyChain");
        _;
    }

    function mintProductNft(address to, string memory tokenUri) external onlySupplyChain returns (uint256) {
        uint256 newId = s_tokenCounter++;
        s_tokenIdToUri[newId] = tokenUri;
        _safeMint(to, newId);
        emit ProductMinted(newId, to);
        return newId;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (bytes(s_tokenIdToUri[tokenId]).length > 0) {
            return s_tokenIdToUri[tokenId];
        }
        if (address(supplyChain) == address(0)) return "";
        string memory json = supplyChain.buildMetadata(tokenId);
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));
    }
}
