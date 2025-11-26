// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SupplyChainRWA} from "src/SupplyChainRWA.sol";

/// @title Integration Tests for SupplyChainRWA
/// @author Omisade Olamiposi
/// @notice Verifies the core state transitions and security invariants of the Supply Chain system.
/// @dev Simulates the "Happy Path" (Success) and "Edge Cases" (Access Control) for the Hackathon Stagenet.
contract SupplyChainTest is Test {
    // --- System Under Test ---
    SupplyChainRWA supplyChain;

    // --- Actors ---
    address supplier = makeAddr("supplier");
    address manufacturer = makeAddr("manufacturer");

    /// @notice Deploys the contract and configures the RBAC (Role Based Access Control).
    function setUp() public {
        supplyChain = new SupplyChainRWA("");

        // Grant system roles to test actors
        supplyChain.grantRole(supplyChain.SUPPLIER_ROLE(), supplier);
        supplyChain.grantRole(supplyChain.MANUFACTURER_ROLE(), manufacturer);
    }

    /// @dev Helper function to setup a valid shipment state.
    ///      Simulates: Minting raw materials -> Approving contract -> Creating Shipment.
    function createDummyShipment() public {
        vm.startPrank(supplier);

        // 1. Supplier mints the raw materials (ERC1155)
        supplyChain.mint(supplier, 1, 100, "");

        // 2. Supplier approves contract to hold goods in Escrow
        supplyChain.setApprovalForAll(address(supplyChain), true);

        // 3. Supplier creates the shipment request
        supplyChain.createShipment(150, 100, 600, manufacturer, 1, 50);

        vm.stopPrank();
    }

    /// @notice Verifies that roles are correctly assigned during deployment.
    /// @dev Critical Security Check: Ensures only authorized addresses hold sensitive roles.
    function testToSeeIfRolesWereAssingnedProperly() public view {
        bool isAdmin = supplyChain.hasRole(supplyChain.DEFAULT_ADMIN_ROLE(), address(this));
        bool isSupplier = supplyChain.hasRole(supplyChain.SUPPLIER_ROLE(), supplier);
        bool isManufacturer = supplyChain.hasRole(supplyChain.MANUFACTURER_ROLE(), manufacturer);

        assertTrue(isAdmin, "Deployer should be Admin");
        assertTrue(isSupplier, "Supplier address should have SUPPLIER_ROLE");
        assertTrue(isManufacturer, "Manufacturer address should have MANUFACTURER_ROLE");
    }

    /// @notice Tests that data is correctly stored in the Shipment struct.
    /// @dev Verifies integrity of the 'shipments' mapping after creation.
    function testCreateShipment() public {
        createDummyShipment();

        (
            int256 destLat,
            int256 destLong,
            uint256 radius,
            address expectedmanufacturer,
            uint256 rawMaterialId,
            uint256 amount,
            SupplyChainRWA.ShipmentStatus status
        ) = supplyChain.shipments(0);

        assertEq(destLat, 150);
        assertEq(destLong, 100);
        assertEq(radius, 600);
        assertEq(expectedmanufacturer, manufacturer);
        assertEq(rawMaterialId, 1);
        assertEq(amount, 50);
        // Ensure status starts at CREATED (0)
        assertEq(uint256(status), uint256(SupplyChainRWA.ShipmentStatus.CREATED));
    }

    /// @notice Security Check: Verifies that unauthorized users cannot create shipments.
    /// @dev Should revert with AccessControlUnauthorizedAccount error.
    function testOnlySupplierCanCreateShipment() public {
        address attacker = makeAddr("attacker");

        vm.startPrank(attacker);
        vm.expectRevert(); // Expect transaction to fail
        supplyChain.createShipment(150, 100, 600, manufacturer, 1, 50);
        vm.stopPrank();
    }

    /// @notice End-to-End Test: Simulates the entire lifecycle from Creation to Delivery.
    /// @dev Tests the Chainlink Automation logic (checkUpkeep -> performUpkeep).
    function testOrderFulfillment() public {
        // 1. Setup
        createDummyShipment();

        // 2. Start Transit
        vm.prank(supplier);
        supplyChain.startDelivery(0);

        bytes memory checkData = abi.encode(0, int256(90), int256(90));

        // 3. Simulate Chainlink Automation (Check)
        // Should return true because status is IN_TRANSIT
        (bool upkeepNeeded, bytes memory performData) = supplyChain.checkUpkeep(checkData);
        assertTrue(upkeepNeeded, "Upkeep should be needed when shipment is in transit");

        // 4. Simulate Chainlink Automation (Perform)
        // Should auto-arrive the shipment (Simulation Logic)
        supplyChain.performUpkeep(performData);

        // 5. Verify Final State
        (,,,,,, SupplyChainRWA.ShipmentStatus status) = supplyChain.shipments(0);

        // Status 2 = ARRIVED
        assertEq(uint256(status), 2, "Shipment status should be ARRIVED");

        // 6. Verify Asset Transfer (Escrow Release)
        // Manufacturer should now have the 50 tokens
        uint256 manufacturerBalance = supplyChain.balanceOf(manufacturer, 1);
        assertEq(manufacturerBalance, 50, "Manufacturer should receive the tokens");
    }

    function testCannotFufillOrderOutsideGeofence() public {
        createDummyShipment();
        vm.startPrank(supplier);
        supplyChain.startDelivery(0);

        bytes memory badData = abi.encode(0, int256(1000), int256(1000));
        supplyChain.performUpkeep(badData);

        (,,,,,, SupplyChainRWA.ShipmentStatus status) = supplyChain.shipments(0);
        assertEq(uint256(status), uint256(SupplyChainRWA.ShipmentStatus.IN_TRANSIT));

        assertEq(supplyChain.balanceOf(manufacturer, 1), 0);
    }

    function testFullfillInsideGeofence() public {
        createDummyShipment();
        vm.startPrank(supplier);
        supplyChain.startDelivery(0);

        bytes memory goodData = abi.encode(0, int256(90), int256(90));
        supplyChain.performUpkeep(goodData);

        (,,,,,, SupplyChainRWA.ShipmentStatus status) = supplyChain.shipments(0);
        assertEq(uint256(status), uint256(SupplyChainRWA.ShipmentStatus.ARRIVED));

        assertEq(supplyChain.balanceOf(manufacturer, 1), 50);
    }
}
