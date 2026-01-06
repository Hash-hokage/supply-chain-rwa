// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {SupplyChainRWA} from "src/SupplyChainRWA.sol";
import {ProductNft} from "src/ProductNft.sol";
import {PaymentEscrow} from "src/PaymentEscrow.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {MockUSDC} from "test/mocks/MockERC20.sol";

contract DeploySystem is Script {
    function run() external returns (SupplyChainRWA, PaymentEscrow, ProductNft, address) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getActiveNetworkConfig();

        uint32 gasLimit = 300000;

        vm.startBroadcast();

        // 1. Deploy Token
        MockUSDC mockUsdc = new MockUSDC();
        address paymentToken = address(mockUsdc);

        // OPTIONAL: Mint 1 Million Test USDC to yourself so you can test payments immediately
        mockUsdc.mint(msg.sender, 1_000_000 * 10 ** 18);
        console.log("Minted 1M MockUSDC to deployer");

        // 2. Deploy NFT
        ProductNft productNft = new ProductNft();

        // 3. Deploy Logic
        SupplyChainRWA supplyChain = new SupplyChainRWA(
            "ipfs://base-uri/", address(productNft), config.router, config.subId, gasLimit, config.donId
        );

        // 4. Deploy Escrow (Linked)
        PaymentEscrow escrow = new PaymentEscrow(address(supplyChain), paymentToken);

        // 5. Wire Permissions
        productNft.setSupplyChain(address(supplyChain));
        console.log("ProductNft wired to SupplyChainRWA");

        vm.stopBroadcast();

        // 6. Log Addresses for your Frontend
        console.log("SupplyChain Address:", address(supplyChain));
        console.log("Escrow Address:", address(escrow));
        console.log("NFT Address:", address(productNft));
        console.log("USDC Address:", address(mockUsdc));

        return (supplyChain, escrow, productNft, paymentToken);
    }
}
