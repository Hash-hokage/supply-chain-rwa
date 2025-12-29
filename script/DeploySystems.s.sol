// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {SupplyChainRWA} from "src/SupplyChainRWA.sol";
import {ProductNft} from "src/ProductNft.sol";
import {PaymentEscrow} from "src/PaymentEscrow.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {MockRouter} from "test/mocks/MockRouter.sol";
import {MockUSDC} from "test/mocks/MockERC20.sol";

contract DeploySystem is Script {
    function run() external returns (SupplyChainRWA, PaymentEscrow, HelperConfig, address) {
        HelperConfig helperConfig = new HelperConfig();

        (,, bytes32 donId, uint64 subId) = helperConfig.activeNetworkConfig();

        uint32 gasLimit = 300000;

        vm.startBroadcast();

        MockUSDC mockUsdc = new MockUSDC();
        address paymentToken = address(mockUsdc);

        MockRouter mockRouter = new MockRouter();

        ProductNft productNft = new ProductNft();

        SupplyChainRWA supplyChain =
            new SupplyChainRWA("ipfs://base-uri/", address(productNft), address(mockRouter), subId, gasLimit, donId);

        PaymentEscrow escrow = new PaymentEscrow(address(supplyChain), paymentToken);

        productNft.setSupplyChain(address(supplyChain));
        //productNft.transferOwnership(address(supplyChain));

        vm.stopBroadcast();

        return (supplyChain, escrow, helperConfig, paymentToken);
    }
}
