// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {SupplyChainRWA} from "src/SupplyChainRWA.sol";

contract InteractStagnet is Script {
    function run() external {
        // 1. Setup Account
        uint256 deployerKey = vm.envUint("STAGENET_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        
        address supplyChainAddr = 0x1E8F843B32C121675A32894D2D85D905857D8Dad; 

        console.log("-------------------------------------------");
        console.log("Interacting with SupplyChain at:", supplyChainAddr);
        console.log("Acting as Supplier:", deployer);
        console.log("-------------------------------------------");

        vm.startBroadcast(deployerKey);
        SupplyChainRWA supplyChain = SupplyChainRWA(supplyChainAddr);

        // 2. Mint 100 Units of Raw Material (ID 1)
        supplyChain.mint(deployer, 1, 100, "");
        console.log("Minted 100 units of Material ID 1");

        // 3. Approve Contract
        supplyChain.setApprovalForAll(supplyChainAddr, true);
        console.log("Approved contract for transfer");

        // 4. Create a Live Shipment
        // Params: Lat: 150, Long: 100, Radius: 600, Receiver: Deployer, ID: 1, Amount: 50
        // Expected Arrival: Now + 1 hour
        supplyChain.createShipment(
            150, 
            100, 
            600, 
            deployer, 
            1, 
            50, 
            block.timestamp + 1 hours, 
            0
        );
        console.log("Shipment #0 created successfully!");
        console.log("Waiting for block confirmation... (Mainnet Replay ~12s)");

        vm.stopBroadcast();
    }
}