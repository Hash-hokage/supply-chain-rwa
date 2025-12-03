// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {SupplyChainRWA} from "src/SupplyChainRWA.sol";
import {ProductNft} from "src/ProductNft.sol";
import {MockRouter} from "test/mocks/MockRouter.sol"; 

contract DeployStagnet is Script {
    function run() external returns (SupplyChainRWA, ProductNft) {
        // 1. Load Env Variables & Derive Address
        uint256 deployerKey = vm.envUint("STAGENET_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerKey); // <--- We calculate this first now
        
        // 2. CONFIGURATION
        address router = address(0); 
        uint64 subId = 1; 
        uint32 gasLimit = 300000;
        bytes32 donId = bytes32("donId"); 

        vm.startBroadcast(deployerKey);

        // 3. Deploy Mock Router (if needed)
        if (router == address(0)) {
            MockRouter mockRouter = new MockRouter();
            router = address(mockRouter);
            console.log("Deployed MockRouter at:", router);
        }

        // 4. Deploy NFT (Passing the Deployer as the Initial Owner)
        // FIX: Added deployerAddress as the argument
        ProductNft productNft = new ProductNft(deployerAddress);
        console.log("ProductNFT deployed at:", address(productNft));

        // 5. Deploy Supply Chain
        SupplyChainRWA supplyChain = new SupplyChainRWA(
            "https://ipfs.io/ipfs/",
            address(productNft),
            router,
            subId,
            gasLimit,
            donId
        );
        console.log("SupplyChainRWA deployed at:", address(supplyChain));

        // 6. Setup Roles
        supplyChain.grantRole(supplyChain.SUPPLIER_ROLE(), deployerAddress);
        supplyChain.grantRole(supplyChain.MANUFACTURER_ROLE(), deployerAddress);
        
        // 7. Grant Minter Role to SupplyChain (Critical for assembly!)
        // Assuming ProductNft has a function to set the minter or uses AccessControl
        // If ProductNft is Ownable, you might not need this line depending on your logic,
        // but typically the SupplyChain needs permission to mint.
        // productNft.setMinter(address(supplyChain)); 

        vm.stopBroadcast();
        return (supplyChain, productNft);
    }
}