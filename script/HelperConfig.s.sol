// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {MockRouter} from "test/mocks/MockRouter.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {
    
    struct NetworkConfig {
        address router;
        address linkToken;
        bytes32 donId;
        uint64 subId;
    }

    NetworkConfig public activeNetworkConfig;

    uint256 public constant MAINNET_CHAIN_ID = 1;

    constructor() {
        if (block.chainid == MAINNET_CHAIN_ID) {
            activeNetworkConfig = getMainnetEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getMainnetEthConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            router: 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0,
            linkToken: 0x514910771AF9Ca656af840dff83E8264EcF986CA,
            donId: bytes32(0x66756e2d657468657265756d2d6d61696e6e65742d3100000000000000000000), // Real DON ID
            subId: 1234 
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.router != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        
        MockRouter mockRouter = new MockRouter();
        ERC20Mock mockLink = new ERC20Mock(); // Standard OpenZeppelin Mock
        
        vm.stopBroadcast();

        return NetworkConfig({
            router: address(mockRouter),
            linkToken: address(mockLink),
            donId: bytes32("donId"),
            subId: 1
        });
    }
}