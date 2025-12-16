// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2, Vm} from "forge-std/Test.sol";
import {SupplyChainRWA} from "src/SupplyChainRWA.sol";
import {MockRouter} from "test/mocks/MockRouter.sol";
import {MockProductNft} from "test/mocks/MockProductNft.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";

contract SupplyChainRWATest is Test {
    using FunctionsRequest for FunctionsRequest.Request;

    SupplyChainRWA public supplyChain;
    MockProductNft public productNft;
    MockRouter public functionsRouter;

    address public admin = makeAddr("admin");
    address public supplier = makeAddr("supplier");
    address public manufacturer = makeAddr("manufacturer");
    address public randomUser = makeAddr("randomUser");

    // Constants based on contract
    uint256 constant MATERIAL_ID_A = 1;
    uint256 constant MATERIAL_AMOUNT = 500;
    uint256 constant SHIPMENT_AMOUNT = 100;

    // GPS Constants (scaled 1e6)
    int256 constant DEST_LAT = 40_712800; // NYC
    int256 constant DEST_LONG = -74_006000;
    uint256 constant RADIUS = 1000; // 1km

    // Events to check
    event ShipmentCreated(uint256 indexed shipmentId, address indexed manufacturer, uint256 expectedArrivalTime);
    event ShipmentArrived(uint256 indexed shipmentId, address indexed manufacturer);
    event ProductAssembled(uint256 indexed shipmentId, address indexed manufacturer, uint256 quantity);

    function setUp() public {
        vm.startPrank(admin);

        // 1. Deploy Infrastructure
        productNft = new MockProductNft();
        functionsRouter = new MockRouter(); // Using your MockRouter

        // 2. Deploy SupplyChain
        supplyChain = new SupplyChainRWA(
            "https://api.supplychain.com/meta/",
            address(productNft),
            address(functionsRouter),
            1, // SubId
            300000, // GasLimit
            bytes32("don-id")
        );

        // 3. Setup Roles
        supplyChain.grantRole(supplyChain.SUPPLIER_ROLE(), supplier);
        supplyChain.grantRole(supplyChain.MANUFACTURER_ROLE(), manufacturer);

        vm.stopPrank();

        // 4. Mint Initial Materials to Supplier
        vm.prank(supplier);
        supplyChain.mint(supplier, MATERIAL_ID_A, MATERIAL_AMOUNT, "");

        // Approve contract to handle materials
        vm.prank(supplier);
        supplyChain.setApprovalForAll(address(supplyChain), true);
    }

    /*//////////////////////////////////////////////////////////////
                            HAPPY PATH FLOW
    //////////////////////////////////////////////////////////////*/

    function test_FullLifecycle_CreationToAssembly() public {
        uint256 eta = block.timestamp + 2 hours;

        // --- 1. Create Shipment ---
        vm.prank(supplier);
        vm.expectEmit(true, true, true, true);
        emit ShipmentCreated(0, manufacturer, eta);

        supplyChain.createShipment(DEST_LAT, DEST_LONG, RADIUS, manufacturer, MATERIAL_ID_A, SHIPMENT_AMOUNT, eta);

        // --- 2. Start Delivery ---
        vm.prank(supplier);
        supplyChain.startDelivery(0);

        // --- 3. Simulate Time Passing & Automation Check ---
        vm.warp(eta + 1 minutes); // Past ETA

        (bool upkeepNeeded, bytes memory performData) = supplyChain.checkUpkeep("");
        assertTrue(upkeepNeeded);

        // --- 4. Perform Upkeep (Triggers Chainlink Functions) ---
        vm.recordLogs();
        supplyChain.performUpkeep(performData);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Extract requestId from Your MockRouter's event
        // Event: RequestSent(bytes32 indexed id)
        // Topic 0: Keccak hash of signature, Topic 1: requestId
        bytes32 requestId = entries[0].topics[1];

        // --- 5. Fulfill Request (Simulate DON Response) ---
        // Since your MockRouter doesn't have a fulfill helper, we impersonate it.
        // The FunctionsClient contract expects a call to `handleOracleFulfillment`

        bytes memory response = abi.encode(DEST_LAT, DEST_LONG);

        vm.expectEmit(true, true, true, true);
        emit ShipmentArrived(0, manufacturer);

        // IMPERSONATION: We pretend to be the router calling back the client
        vm.prank(address(functionsRouter));
        supplyChain.handleOracleFulfillment(requestId, response, bytes(""));

        // Assert: Status Arrived
        assertEq(supplyChain.getShipmentStatus(0), 2); // 2 = ARRIVED
        assertEq(supplyChain.balanceOf(manufacturer, MATERIAL_ID_A), SHIPMENT_AMOUNT);

        // --- 6. Assemble Product ---
        string[] memory uris = new string[](SHIPMENT_AMOUNT);
        for (uint256 i = 0; i < SHIPMENT_AMOUNT; i++) {
            uris[i] = "ipfs://metadata";
        }

        vm.prank(manufacturer);
        supplyChain.assembleProduct(0, uris);

        // Assert: Materials Burned, NFTs Minted
        assertEq(supplyChain.balanceOf(manufacturer, MATERIAL_ID_A), 0); // Burned
        assertEq(productNft.balanceOf(manufacturer), SHIPMENT_AMOUNT); // Minted
    }

    /*//////////////////////////////////////////////////////////////
                        LOGIC & CONSTRAINT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GPSDistanceCalculation() public {
        uint256 eta = block.timestamp + 2 hours;

        vm.prank(supplier);
        supplyChain.createShipment(DEST_LAT, DEST_LONG, RADIUS, manufacturer, MATERIAL_ID_A, SHIPMENT_AMOUNT, eta);
        vm.prank(supplier);
        supplyChain.startDelivery(0);

        vm.warp(eta + 1);
        (, bytes memory performData) = supplyChain.checkUpkeep("");

        vm.recordLogs();
        supplyChain.performUpkeep(performData);
        bytes32 requestId = vm.getRecordedLogs()[0].topics[1];

        // Simulate location OUTSIDE radius
        int256 badLat = DEST_LAT + 2000;
        bytes memory response = abi.encode(badLat, DEST_LONG);

        // Impersonate Router
        vm.prank(address(functionsRouter));
        supplyChain.handleOracleFulfillment(requestId, response, bytes(""));

        // Should NOT be arrived yet
        assertEq(supplyChain.getShipmentStatus(0), 1); // Still IN_TRANSIT
    }

    function test_RevertIf_ETAInvalid() public {
        vm.startPrank(supplier);
        vm.expectRevert(SupplyChainRWA.InvalidETA.selector);
        supplyChain.createShipment(DEST_LAT, DEST_LONG, RADIUS, manufacturer, MATERIAL_ID_A, 10, block.timestamp);
        vm.stopPrank();
    }
}
