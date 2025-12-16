// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {SupplyChainRWA} from "src/SupplyChainRWA.sol";
import {ProductNft} from "src/ProductNft.sol";
import {MockRouter} from "test/mocks/MockRouter.sol";

contract DeployStagnet is Script {
    function run() external returns (SupplyChainRWA, ProductNft) {
        // Load deployer key
        uint256 deployerKey = vm.envUint("STAGENET_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("Deploying from:", deployer);

        // Dummy Chainlink config (ignored by mock)
        uint64 subId = 1;
        uint32 gasLimit = 300_000;
        bytes32 donId = bytes32("mock-don-id");

        vm.startBroadcast(deployerKey);

        // 1. Deploy your existing MockRouter
        MockRouter mockRouter = new MockRouter();
        console.log("MockRouter deployed at:", address(mockRouter));

        // 2. Deploy ProductNft
        ProductNft productNft = new ProductNft();
        console.log("ProductNft deployed at:", address(productNft));

        // 3. Deploy SupplyChainRWA using the mock
        SupplyChainRWA supplyChain = new SupplyChainRWA(
            "ipfs://QmRawMaterialBaseUri/", address(productNft), address(mockRouter), subId, gasLimit, donId
        );
        console.log("SupplyChainRWA deployed at:", address(supplyChain));

        // 4. Critical wiring: connect ProductNft → SupplyChain
        productNft.setSupplyChain(address(supplyChain));
        console.log("ProductNft successfully wired to SupplyChainRWA");

        // 5. Grant roles to deployer for easy testing
        supplyChain.grantRole(supplyChain.SUPPLIER_ROLE(), deployer);
        supplyChain.grantRole(supplyChain.MANUFACTURER_ROLE(), deployer);
        console.log("Granted SUPPLIER_ROLE and MANUFACTURER_ROLE to deployer");

        vm.stopBroadcast();

        console.log("=== Deployment Complete on Stagenet ===");
        console.log("Use manufacturerForceArrival() or forceArrival() to simulate delivery");
        console.log("MockRouter is active no real Chainlink needed yet");

        return (supplyChain, productNft);
    }
}
