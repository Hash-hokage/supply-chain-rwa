// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, Vm} from "forge-std/Test.sol";
import {SupplyChainRWA} from "src/SupplyChainRWA.sol";
import {ProductNft} from "src/ProductNft.sol";

contract SupplyChainTest is Test {
    // --- System Under Test ---

    SupplyChainRWA supplyChain = new SupplyChainRWA("uri", address(0), router, subId, gasLimit, donId); // deploy SupplyChain first
    ProductNft productNft = new ProductNft(address(supplyChain)); // pass the SupplyChain address

    // --- Actors ---
    address supplier = makeAddr("supplier");
    address manufacturer = makeAddr("manufacturer");
    address otherUser = makeAddr("otherUser");
    // --- Mock Chainlink Config ---
    address router = makeAddr("router");
    uint64 subId = 1234;
    uint32 gasLimit = 300000;
    // forge-lint: disable-next-line(unsafe-typecast)
    bytes32 donId = bytes32("donId");

    function setUp() public {
        // We now pass ALL 6 arguments to match the new constructor
        supplyChain = new SupplyChainRWA(
            "uri", // 1. URI
            address(productNft), // 2. NFT Address
            router, // 3. Chainlink Router
            subId, // 4. Subscription ID
            gasLimit, // 5. Gas Limit
            donId // 6. DON ID
        );

        // Grant system roles to test actors
        supplyChain.grantRole(supplyChain.SUPPLIER_ROLE(), supplier);
        supplyChain.grantRole(supplyChain.MANUFACTURER_ROLE(), manufacturer);
    }

    function createDummyShipment() public {
        vm.startPrank(supplier);

        supplyChain.mint(supplier, 1, 100, "");
        supplyChain.setApprovalForAll(address(supplyChain), true);

        // FIX 2: Updated createShipment with Time Args
        // expectedArrivalTime = block.timestamp + 1 day
        // lastCheckTimestamp = 0
        supplyChain.createShipment(150, 100, 600, manufacturer, 1, 50, block.timestamp + 1 days, 0);

        vm.stopPrank();
    }

    function testToSeeIfRolesWereAssingnedProperly() public view {
        bool isAdmin = supplyChain.hasRole(supplyChain.DEFAULT_ADMIN_ROLE(), address(this));
        bool isSupplier = supplyChain.hasRole(supplyChain.SUPPLIER_ROLE(), supplier);
        bool isManufacturer = supplyChain.hasRole(supplyChain.MANUFACTURER_ROLE(), manufacturer);

        assertTrue(isAdmin, "Deployer should be Admin");
        assertTrue(isSupplier, "Supplier address should have SUPPLIER_ROLE");
        assertTrue(isManufacturer, "Manufacturer address should have MANUFACTURER_ROLE");
    }

    function testCreateShipment() public {
        createDummyShipment();

        // FIX 3: Updated Struct Decoding (9 variables now)
        (
            int256 destLat,
            int256 destLong,
            uint256 radius,
            address expectedmanufacturer,
            uint256 rawMaterialId,
            uint256 amount,
            SupplyChainRWA.ShipmentStatus status,
            uint256 expectedTime, // New Field
            uint256 lastCheck // New Field
        ) = supplyChain.shipments(0);

        assertEq(destLat, 150);
        assertEq(destLong, 100);
        assertEq(radius, 600);
        assertEq(expectedmanufacturer, manufacturer);
        assertEq(rawMaterialId, 1);
        assertEq(amount, 50);
        assertEq(uint256(status), uint256(SupplyChainRWA.ShipmentStatus.CREATED));
        assertEq(expectedTime, block.timestamp + 1 days);
        assertEq(lastCheck, 0);
    }

    function testOnlySupplierCanCreateShipment() public {
        address attacker = makeAddr("attacker");

        vm.startPrank(attacker);
        vm.expectRevert();
        // FIX 4: Updated createShipment args here too
        supplyChain.createShipment(150, 100, 600, manufacturer, 1, 50, block.timestamp + 1 days, 0);
        vm.stopPrank();
    }

    // NOTE: This test will compile but logic might fail because
    // performUpkeep now sends a Request instead of finishing immediately.
    // We can fix the logic once it compiles.
    function testOrderFulfillment() public {
        // 1. Setup Shipment
        createDummyShipment();

        // 2. Start Delivery
        vm.prank(supplier);
        supplyChain.startDelivery(0);

        // 3. Fast Forward Time to unlock the "Smart Polling" window
        vm.warp(block.timestamp + 1 days + 1);

        // 4. Check Upkeep
        bytes memory checkData = "";
        (bool upkeepNeeded, bytes memory performData) = supplyChain.checkUpkeep(checkData);
        assertTrue(upkeepNeeded, "Upkeep should be needed");

        // 5. Mock the Router Response
        // We define a known ID so we don't have to hunt for it in logs
        bytes32 mockRequestId = bytes32("request_1");

        // We intercept the call to 'sendRequest' on the router address
        // Signature matches: sendRequest(uint64,bytes,uint8,uint32,bytes32)
        vm.mockCall(
            router,
            abi.encodeWithSignature("sendRequest(uint64,bytes,uint16,uint32,bytes32)"),
            abi.encode(mockRequestId)
        );

        // 6. Trigger Perform Upkeep (sends the request)
        supplyChain.performUpkeep(performData);

        // 7. Simulate Chainlink Callback
        // Use coordinates (150, 100) which match the destination
        bytes memory response = abi.encode(int256(150), int256(100), uint256(1));
        bytes memory err = "";

        // Impersonate the router to deliver the data
        vm.prank(router);
        supplyChain.handleOracleFulfillment(mockRequestId, response, err);

        // 8. Final Assertions
        // Verify Status is ARRIVED (Enum index 2)
        (,,,,,, SupplyChainRWA.ShipmentStatus status,,) = supplyChain.shipments(0);
        assertEq(uint256(status), uint256(SupplyChainRWA.ShipmentStatus.ARRIVED), "Status should be ARRIVED");

        // Verify Manufacturer got paid (50 tokens)
        assertEq(supplyChain.balanceOf(manufacturer, 1), 50, "Manufacturer should receive tokens");
    }

    function testCannotFulfillOrderOutsideGeofence() public {
        // 1. Setup
        createDummyShipment();
        vm.prank(supplier);
        supplyChain.startDelivery(0);

        // 2. Mock the Request
        // We need a valid Request ID to pass to the fulfillment function
        bytes32 mockRequestId = bytes32("request_fail_geo");
        vm.mockCall(
            router,
            abi.encodeWithSignature("sendRequest(uint64,bytes,uint16,uint32,bytes32)"),
            abi.encode(mockRequestId)
        );
        
        // Trigger the request
        vm.warp(block.timestamp + 1 days + 1); // Time travel to open window
        bytes memory performData = abi.encode(uint256(0));
        supplyChain.performUpkeep(performData);

        // 3. Simulate "Bad" Data
        // Destination is (150, 100). We send (1000, 1000).
        bytes memory badResponse = abi.encode(int256(1000), int256(1000), uint256(1));
        bytes memory err = "";

        // 4. Deliver Data
        vm.prank(router);
        supplyChain.handleOracleFulfillment(mockRequestId, badResponse, err);

        // 5. Verify Nothing Changed
        (,,,,,, SupplyChainRWA.ShipmentStatus status,,) = supplyChain.shipments(0);
        
        // Status should still be IN_TRANSIT (1), NOT ARRIVED (2)
        assertEq(uint256(status), uint256(SupplyChainRWA.ShipmentStatus.IN_TRANSIT), "Should not arrive outside geofence");
        
        // Manufacturer should NOT have tokens
        assertEq(supplyChain.balanceOf(manufacturer, 1), 0, "Assets should remain in escrow");
    }

    function testOnlySupplierCanStartDelivery() public {
        createDummyShipment();
        
        // Create an unauthorized attacker
        address attacker = makeAddr("attacker");
        
        vm.startPrank(attacker);
        
        // We expect the next line to revert because attacker lacks SUPPLIER_ROLE
        vm.expectRevert(); 
        supplyChain.startDelivery(0);
        
        vm.stopPrank();
    }

    function testCannotFulfillAlreadyArrivedShipment() public {
        // 1. Complete a valid delivery first (Happy Path)
        testOrderFulfillment(); 

        // Verify it is arrived
        (,,,,,, SupplyChainRWA.ShipmentStatus status,,) = supplyChain.shipments(0);
        assertEq(uint256(status), uint256(SupplyChainRWA.ShipmentStatus.ARRIVED));

        // 2. Try to fulfill it AGAIN
        bytes32 newRequestId = bytes32("request_replay");
        bytes memory response = abi.encode(int256(150), int256(100), uint256(1));
        bytes memory err = "";

        // Since we manually mapped the request ID in the first test, 
        // we need to manually map this new fake ID to shipment 0 for the test logic to find it
        // (In production, performUpkeep would do this, but we are skipping straight to the callback here)
        // Note: Accessing the mapping directly in test requires a "harness" or just repeating the setup.
        // EASIER STRATEGY: Just use the OLD request ID that is already mapped!
        
        bytes32 oldRequestId = bytes32("request_1"); // From testOrderFulfillment

        vm.prank(router);
        
        // We expect a revert because the contract checks: require(status == IN_TRANSIT)
        vm.expectRevert();
        supplyChain.handleOracleFulfillment(oldRequestId, response, err);
    }

    ///MANUFACTURING LOGIC TESTS
}
