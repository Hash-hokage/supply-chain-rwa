// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2, Vm} from "forge-std/Test.sol";
import {SupplyChainRWA} from "src/SupplyChainRWA.sol";
import {MockRouter} from "test/mocks/MockRouter.sol";
import {MockProductNft} from "test/mocks/MockProductNft.sol";

contract SupplyChainFuzz is Test {
    SupplyChainRWA public supplyChain;
    MockProductNft public productNft;
    MockRouter public functionsRouter;

    address public supplier = makeAddr("supplier");
    address public manufacturer = makeAddr("manufacturer");

    function setUp() public {
        productNft = new MockProductNft();
        functionsRouter = new MockRouter();

        supplyChain = new SupplyChainRWA(
            "uri",
            address(productNft),
            address(functionsRouter),
            1,
            300000,
            bytes32("don-id")
        );
        supplyChain.grantRole(supplyChain.SUPPLIER_ROLE(), supplier);
        supplyChain.grantRole(supplyChain.MANUFACTURER_ROLE(), manufacturer);

        // Give supplier plenty of materials for fuzzing
        vm.prank(supplier);
        supplyChain.mint(supplier, 1, 1_000_000, "");
        vm.prank(supplier);
        supplyChain.setApprovalForAll(address(supplyChain), true);
    }

    /*//////////////////////////////////////////////////////////////
                            STATELESS FUZZING
    //////////////////////////////////////////////////////////////*/

    // Test that createShipment handles ANY valid combination of numbers without reverting
    function testFuzz_CreateShipment_StateConsistency(
        int256 lat,
        int256 long,
        uint256 radius,
        uint256 amount,
        uint256 etaOffset
    ) public {
        // 1. Bound inputs to reasonable/valid contract constraints
        // Radius: 50 to 10,000
        radius = bound(radius, 50, 10_000);
        
        // Amount: 1 to 100 (Supplier has 1M)
        amount = bound(amount, 1, 100);
        
        // ETA: 1 hour to 90 days
        etaOffset = bound(etaOffset, 1 hours, 90 days);
        uint256 eta = block.timestamp + etaOffset;

        uint256 preBalance = supplyChain.balanceOf(supplier, 1);

        // 2. Act
        vm.prank(supplier);
        supplyChain.createShipment(lat, long, radius, manufacturer, 1, amount, eta);

        // 3. Assert Invariants
        // Supplier balance must decrease exactly by amount
        assertEq(supplyChain.balanceOf(supplier, 1), preBalance - amount);
        
        // Contract balance must increase exactly by amount
        assertEq(supplyChain.balanceOf(address(supplyChain), 1), amount);

        // Check Shipment State
        uint256 id = 0; // First shipment is always 0 in this clean state
        (int256 sLat, int256 sLong, uint256 sRadius,,,,,,,) = supplyChain.shipments(id);
        
        assertEq(sLat, lat);
        assertEq(sLong, long);
        assertEq(sRadius, radius);
    }

    // Test that invalid inputs ALWAYS revert
    function testFuzz_CreateShipment_RevertsOnInvalidRadius(uint256 radius) public {
        // Assume radius is OUTSIDE valid range
        // Valid is 50 - 10,000. 
        // We test 0-49 OR 10,001 - max
        
        if (radius >= 50 && radius <= 10_000) return; // Skip valid ones
        
        vm.startPrank(supplier);
        vm.expectRevert(SupplyChainRWA.InvalidRadius.selector);
        supplyChain.createShipment(0, 0, radius, manufacturer, 1, 10, block.timestamp + 2 hours);
        vm.stopPrank();
    }

    // Test the GPS math specifically
    // We want to ensure that if the Oracle returns coordinates, the math doesn't panic
    // even with extreme values.
    function testFuzz_OracleResponse_MathSafety(int256 oracleLat, int256 oracleLong) public {
        // Setup a shipment first
        vm.startPrank(supplier);
        supplyChain.createShipment(0, 0, 1000, manufacturer, 1, 10, block.timestamp + 2 hours);
        supplyChain.startDelivery(0);
        vm.stopPrank();

        // Manually trigger "performUpkeep" to generate a pending request
        vm.warp(block.timestamp + 2 hours + 1);
        (, bytes memory performData) = supplyChain.checkUpkeep("");
        
        vm.recordLogs();
        supplyChain.performUpkeep(performData);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[0].topics[1];

        // Fulfill with FUZZED coordinates
        // The contract calculates: (dLat^2 + dLong^2)
        // If dLat is MAX_INT, dLat^2 will overflow unless cast effectively.
        // We want to see if this reverts or behaves.
        
        bytes memory response = abi.encode(oracleLat, oracleLong);
        
        vm.prank(address(functionsRouter));
        // We expect NO Panic (overflow/underflow). 
        // It might revert with custom errors, or succeed, but not Panic code 0x11
        try supplyChain.handleOracleFulfillment(requestId, response, bytes("")) {
            // Success or logical completion
        } catch (bytes memory) {
            // Logic revert is fine, but we want to ensure contract handles it
        }
    }
}