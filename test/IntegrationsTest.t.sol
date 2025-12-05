// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {SupplyChainRWA} from "src/SupplyChainRWA.sol";
import {ProductNft} from "src/ProductNft.sol";
import {MockRouter} from "test/mocks/MockRouter.sol";

/// @title SupplyChainRWA Integration Tests (manufacturing-focused)
/// @notice Integration tests for the manufacturing/assembly logic using Foundry.
/// @dev Keep the tests focused on assembleProduct and related state transitions.
contract SupplyChainRWAIntegrationTest is Test {
    // Actors (use makeAddr helpers for easy addresses)
    address supplier = makeAddr("supplier");
    address manufacturer = makeAddr("manufacturer");
    address otherUser = makeAddr("otherUser");
    address router = makeAddr("router");

    // Chainlink / router config (same style as your provided tests)
    uint64 subId = 1234;
    uint32 gasLimit = 300000;
    bytes32 donId = bytes32("donId");

    // Raw material token id we'll use
    uint256 constant RAW_ID = 1;

    // Helpers to deploy fresh contracts for each test
    function _setUpActors() internal returns (SupplyChainRWA sc, ProductNft pn, MockRouter mr) {
        // Deploy a mock router (or use existing router address)
        mr = new MockRouter();

        // Deploy ProductNft first with a harmless supplyChain address (doesn't affect mint)
        pn = new ProductNft(address(this)); // supplyChain address stored in PN is not used by mintProductNft

        // Deploy SupplyChain and point to the ProductNft contract
        sc = new SupplyChainRWA("uri", address(pn), address(mr), subId, gasLimit, donId);

        // Grant roles to supplier & manufacturer
        sc.grantRole(sc.SUPPLIER_ROLE(), supplier);
        sc.grantRole(sc.MANUFACTURER_ROLE(), manufacturer);

        // If ProductNft.tokenURI needs the supplyChain later, we could redeploy PN with sc address.
        // But mintProductNft does not require PN.supplyChain, so this is OK for these tests.
    }

    /// Mint raw materials to supplier and approve supplyChain to transfer them
    function _mintRawMaterials(SupplyChainRWA sc, uint256 amount) internal {
        vm.startPrank(supplier);
        sc.mint(supplier, RAW_ID, amount, "");
        // Approve the supplyChain contract to transfer supplier's tokens (escrow step in createShipment)
        sc.setApprovalForAll(address(sc), true);
        vm.stopPrank();
    }

    /// Create a shipment from supplier -> manufacturer and return shipmentId (first shipment -> id 0)
    /// This matches createShipment signature in your contract (with expectedArrivalTime + lastCheckTimestamp)
    function _createShipmentFixture(SupplyChainRWA sc, uint256 amount) internal returns (uint256 shipmentId) {
        vm.startPrank(supplier);
        // createShipment(destLat, destLong, radius, manufacturer, rawMaterialId, amount, expectedArrivalTime, lastCheckTimestamp)
        sc.createShipment(0, 0, 1000, manufacturer, RAW_ID, amount, block.timestamp + 1 days, 0);
        vm.stopPrank();
        return 0;
    }

    /// Trigger shipment arrival via performUpkeep + router callback (mocks router and response).
    /// This follows the same mocking strategy used in your existing tests.
    function _triggerShipmentArrival(SupplyChainRWA sc, MockRouter mr, uint256 shipmentId) internal {
        // start delivery
        vm.prank(supplier);
        sc.startDelivery(shipmentId);

        // time warp to satisfy checkUpkeep timing
        vm.warp(block.timestamp + 1 days + 1);

        // Prepare mocked request id and intercept call to router.sendRequest
        bytes32 requestId = bytes32("req_integration");
        vm.mockCall(
            address(mr),
            abi.encodeWithSignature("sendRequest(uint64,bytes,uint16,uint32,bytes32)"),
            abi.encode(requestId)
        );

        // Call performUpkeep (encodes args and calls router.sendRequest via FunctionsClient)
        sc.performUpkeep(abi.encode(shipmentId));

        // Simulate the oracle/ router callback with coordinates inside geofence
        bytes memory response = abi.encode(int256(0), int256(0), uint256(1));
        bytes memory err = "";

        // Call the callback as router
        vm.prank(address(mr));
        // The contract uses a FunctionsClient callback mapping -> this test uses the same handleOracleFulfillment name
        sc.handleOracleFulfillment(requestId, response, err);
    }

    /// Perform assembly as manufacturer with given metadata URIs (length must equal shipment.amount)
    function _performAssembly(SupplyChainRWA sc, uint256 shipmentId, string[] memory metadataURIs) internal {
        vm.prank(manufacturer);
        sc.assembleProduct(shipmentId, metadataURIs);
    }

    /* ============================================
       1) Happy path: end-to-end integration test
       ============================================ */

    function test_Integration_FullLifecycle_Succeeds() public {
        (SupplyChainRWA sc, ProductNft pn, MockRouter mr) = _setUpActors();

        // Mint raw materials (amount = 2)
        uint256 amount = 2;
        _mintRawMaterials(sc, amount);

        // Create shipment
        uint256 shipmentId = _createShipmentFixture(sc, amount);

        // Now trigger arrival (startDelivery + performUpkeep + callback)
        _triggerShipmentArrival(sc, mr, shipmentId);

        // Ensure manufacturer received the tokens from escrow (released on arrival)
        assertEq(sc.balanceOf(manufacturer, RAW_ID), amount, "manufacturer should have raw materials after arrival");

        // Prepare metadata URIs array in memory matching amount
        string[] memory metadataURIs = new string[](amount);
        metadataURIs[0] = "ipfs://meta-0";
        metadataURIs[1] = "ipfs://meta-1";

        // Expect ProductAssembled event to be emitted with correct params
        vm.expectEmit(true, true, true, true);
        emit SupplyChainRWA.ProductAssembled(shipmentId, manufacturer, amount);

        // Gas snapshot around assembleProduct call
        uint256 gstart = gasleft();
        vm.prank(manufacturer);
        sc.assembleProduct(shipmentId, metadataURIs);
        uint256 gused = gstart - gasleft();
        console.log("assembleProduct gas used (integration):", gused);

        // Raw materials should be burned
        assertEq(sc.balanceOf(manufacturer, RAW_ID), 0, "raw materials must be burned after assembly");

        // Product NFTs minted to manufacturer (ProductNft.mintProductNft increments token ids starting at 0)
        assertEq(pn.balanceOf(manufacturer), amount, "manufacturer must own minted product NFTs");

        // Validate productToShipment and productToRawMaterial mappings for first two productIds (0 and 1)
        assertEq(sc.productToShipment(0), shipmentId, "product 0 -> shipment mapping");
        assertEq(sc.productToShipment(1), shipmentId, "product 1 -> shipment mapping");

        // Check raw material mapping entries
        // If it's a nested mapping:
        // Check raw material mapping entries
        assertEq(sc.productToRawMaterial(0, 0), RAW_ID, "product 0 raw material recorded");
        assertEq(sc.productToRawMaterial(1, 0), RAW_ID, "product 1 raw material recorded");

        // productAssemblyTimestamp set
        assertGt(sc.productAssemblyTimestamp(0), 0, "assembly timestamp for product 0");
        assertGt(sc.productAssemblyTimestamp(1), 0, "assembly timestamp for product 1");
    }

    /* ============================================
       2) Revert tests: unauthorized manufacturer
       ============================================ */

    function test_Integration_UnauthorizedManufacturerReverts() public {
        (SupplyChainRWA sc,, MockRouter mr) = _setUpActors();

        // Create and deliver shipment
        _mintRawMaterials(sc, 1);
        uint256 shipmentId = _createShipmentFixture(sc, 1);
        _triggerShipmentArrival(sc, mr, shipmentId);

        // Create a DIFFERENT manufacturer who HAS the role but isn't assigned
        address differentManufacturer = makeAddr("different_manufacturer");
        sc.grantRole(sc.MANUFACTURER_ROLE(), differentManufacturer);

        string[] memory metadataURIs = new string[](1);
        metadataURIs[0] = "ipfs://meta";

        // Different manufacturer (has role but not assigned) tries to assemble
        vm.prank(differentManufacturer);
        vm.expectRevert(bytes("Not authorized manufacturer"));
        sc.assembleProduct(shipmentId, metadataURIs);
    }

    /* ============================================
       3) Revert tests: shipment not arrived
       ============================================ */

    function test_Integration_ShipmentNotArrivedReverts() public {
        (SupplyChainRWA sc,,) = _setUpActors();

        // Mint raw materials & create shipment but DO NOT deliver (do not call startDelivery/performUpkeep)
        _mintRawMaterials(sc, 1);
        _createShipmentFixture(sc, 1);

        string[] memory metadataURIs = new string[](1);
        metadataURIs[0] = "ipfs://meta";

        // Manufacturer tries to assemble -> modifier onlyArrived should revert with exact message
        vm.prank(manufacturer);
        vm.expectRevert(bytes("Shipment not arrived"));
        sc.assembleProduct(0, metadataURIs);
    }

    /* ============================================
       4) Revert: insufficient raw materials
       ============================================ */

    function test_Integration_InsufficientRawMaterialsReverts() public {
        (SupplyChainRWA sc,, MockRouter mr) = _setUpActors();

        // Fix: Mint 2 tokens, create shipment, then manufacturer loses 1 token
        vm.startPrank(supplier);
        sc.mint(supplier, RAW_ID, 2, ""); // Mint 2 tokens
        sc.setApprovalForAll(address(sc), true);
        // Create shipment with 2 tokens (both go to escrow)
        sc.createShipment(0, 0, 1000, manufacturer, RAW_ID, 2, block.timestamp + 1 days, 0);
        vm.stopPrank();

        // Shipment arrives, manufacturer gets 2 tokens
        _triggerShipmentArrival(sc, mr, 0);

        // Manufacturer transfers 1 token away (now only has 1)
        vm.prank(manufacturer);
        sc.safeTransferFrom(manufacturer, address(0xdead), RAW_ID, 1, "");

        // Now manufacturer tries to assemble with 2 URIs but only has 1 token
        string[] memory metadataURIs = new string[](2);
        metadataURIs[0] = "ipfs://meta0";
        metadataURIs[1] = "ipfs://meta1";

        // Should revert with "Not enough raw materials"
        vm.prank(manufacturer);
        vm.expectRevert(bytes("Not enough raw materials"));
        sc.assembleProduct(0, metadataURIs);
    }

    /* ============================================
       5) Revert: metadata URI count mismatch
       ============================================ */

    function test_Integration_MetadataURICountMismatchReverts() public {
        (SupplyChainRWA sc,, MockRouter mr) = _setUpActors();

        // create/deliver amount = 2
        _mintRawMaterials(sc, 2);
        _createShipmentFixture(sc, 2);
        _triggerShipmentArrival(sc, mr, 0);

        // Provide only 1 metadata URI while amount == 2 -> should revert with exact message
        string[] memory metadataURIs = new string[](1);
        metadataURIs[0] = "ipfs://only-one";

        vm.prank(manufacturer);
        vm.expectRevert(bytes("Metadata list must match raw material amount"));
        sc.assembleProduct(0, metadataURIs);
    }

    /* ============================================
       6) Revert: shipment already used
       ============================================ */

    function test_Integration_ShipmentAlreadyUsedReverts() public {
        (SupplyChainRWA sc, ProductNft pn, MockRouter mr) = _setUpActors();

        // create/deliver amount = 1
        _mintRawMaterials(sc, 1);
        _createShipmentFixture(sc, 1);
        _triggerShipmentArrival(sc, mr, 0);

        // First assembly should succeed
        string[] memory metadataURIs = new string[](1);
        metadataURIs[0] = "ipfs://first";
        vm.prank(manufacturer);
        sc.assembleProduct(0, metadataURIs);

        // Second attempt should revert with exact message
        vm.prank(manufacturer);
        vm.expectRevert(bytes("Shipment already used"));
        sc.assembleProduct(0, metadataURIs);
    }
}
