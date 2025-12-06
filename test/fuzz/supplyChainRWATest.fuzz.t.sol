// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SupplyChainRWA} from "src/SupplyChainRWA.sol";
import {ProductNft} from "src/ProductNft.sol";
import {MockRouter} from "test/mocks/MockRouter.sol";

contract SupplyChainRWA_FuzzTest is Test {
    SupplyChainRWA supplyChain;
    ProductNft productNft;
    MockRouter mockRouter;

    address supplier = makeAddr("supplier");
    address manufacturer = makeAddr("manufacturer");
    uint256 constant RAW_ID = 1;

    function setUp() public {
        mockRouter = new MockRouter();
        productNft = new ProductNft(address(this));
        // Deploy SupplyChain
        supplyChain = new SupplyChainRWA("uri", address(productNft), address(mockRouter), 1234, 300000, bytes32("donId"));
        
        // Setup Roles
        supplyChain.grantRole(supplyChain.SUPPLIER_ROLE(), supplier);
        supplyChain.grantRole(supplyChain.MANUFACTURER_ROLE(), manufacturer);
    }

    // --- Helpers ---
    function _mintAndCreateShipment(uint256 amount) internal returns (uint256) {
        vm.startPrank(supplier);
        supplyChain.mint(supplier, RAW_ID, amount, "");
        supplyChain.setApprovalForAll(address(supplyChain), true);
        supplyChain.createShipment(0, 0, 1000, manufacturer, RAW_ID, amount, block.timestamp + 1 days, 0);
        vm.stopPrank();
        return 0; // shipmentId
    }

    function _triggerArrival(uint256 shipmentId) internal {
        vm.prank(supplier);
        supplyChain.startDelivery(shipmentId);

        vm.warp(block.timestamp + 1 days + 1);
        
        bytes32 requestId = bytes32("req_fuzz");
        vm.mockCall(
            address(mockRouter),
            abi.encodeWithSignature("sendRequest(uint64,bytes,uint16,uint32,bytes32)"),
            abi.encode(requestId)
        );
        supplyChain.performUpkeep(abi.encode(shipmentId));

        vm.prank(address(mockRouter));
        supplyChain.handleOracleFulfillment(requestId, abi.encode(int256(0), int256(0), uint256(1)), "");
    }

    // ==========================================
    // 1. HAPPY PATH FUZZING
    // ==========================================
    function testFuzz_Integration_Lifecycle_Works(uint256 amount) public {
        // limit amount to realistic values (1 to 500) to avoid overflows/OOG
        amount = bound(amount, 1, 500);

        // Run the flow
        uint256 shipmentId = _mintAndCreateShipment(amount);
        _triggerArrival(shipmentId);

        // Create dynamic metadata array
        string[] memory metadataURIs = new string[](amount);
        for(uint256 i = 0; i < amount; i++) {
            metadataURIs[i] = "ipfs://test";
        }

        vm.prank(manufacturer);
        supplyChain.assembleProduct(shipmentId, metadataURIs);

        // Verify End State
        assertEq(productNft.balanceOf(manufacturer), amount);
        assertEq(supplyChain.balanceOf(manufacturer, RAW_ID), 0);
    }

    // ==========================================
    // 2. REVERT PATH FUZZING
    // ==========================================
    // 1. Define the error at the top of your contract or inside the test contract
    // (OpenZeppelin's AccessControl uses this specific error signature)
    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);

    function testFuzz_RevertIf_UnauthorizedManufacturer(address attacker) public {
        vm.assume(attacker != manufacturer && attacker != supplier);

        // ... setup code ...
        uint256 amount = 1;
        uint256 shipmentId = _mintAndCreateShipment(amount);
        _triggerArrival(shipmentId);

        string[] memory metadataURIs = new string[](amount);
        metadataURIs[0] = "ipfs://hack";

        // --- THE FIX ---
        // 1. Set the expectation first
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector, 
                attacker, 
                supplyChain.MANUFACTURER_ROLE()
            )
        );
        
        // 2. Then set the actor
        vm.prank(attacker);
        
        // 3. Finally, make the call
        supplyChain.assembleProduct(shipmentId, metadataURIs);
    }
}