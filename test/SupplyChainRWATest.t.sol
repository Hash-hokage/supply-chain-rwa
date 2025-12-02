// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SupplyChainRWA} from "src/SupplyChainRWA.sol";
import {ProductNft} from "src/ProductNft.sol";

contract SupplyChainTest is Test {
    // --- System Under Test ---
    SupplyChainRWA supplyChain;
    ProductNft productNft = new ProductNft();

    // --- Actors ---
    address supplier = makeAddr("supplier");
    address manufacturer = makeAddr("manufacturer");

    // --- Mocks ---
    address router = makeAddr("router"); // Mock Chainlink Router
    uint64 subId = 1234;
    uint32 gasLimit = 300000;
    bytes32 donId = bytes32("donId");

    function setUp() public {
        // FIX 1: Updated Constructor with Chainlink Args
        supplyChain = new SupplyChainRWA("", address(productNft), router, subId, gasLimit, donId);

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
        createDummyShipment();

        vm.prank(supplier);
        supplyChain.startDelivery(0);

        // FIX 5: checkUpkeep now returns (true, encodedId)
        // We warp time to ensure upkeep is needed
        vm.warp(block.timestamp + 1 days + 1);

        bytes memory checkData = ""; // No longer used in logic
        (bool upkeepNeeded, bytes memory performData) = supplyChain.checkUpkeep(checkData);

        assertTrue(upkeepNeeded, "Upkeep should be needed");

        // Decoding logic in test
        (uint256 id) = abi.decode(performData, (uint256));
        assertEq(id, 0);
    }
}
