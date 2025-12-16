// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2, Vm} from "forge-std/Test.sol";
import {PaymentEscrow} from "../src/PaymentEscrow.sol";
import {SupplyChainRWA} from "../src/SupplyChainRWA.sol";
import {MockUSDC} from "test/mocks/MockERC20.sol";
import {MockProductNft} from "test/mocks/MockProductNft.sol";
import {MockRouter} from "test/mocks/MockRouter.sol";

contract PaymentEscrowTest is Test {
    PaymentEscrow public escrow;
    SupplyChainRWA public supplyChain;
    MockUSDC public usdc;
    MockProductNft public productNft;
    MockRouter public functionsRouter;

    address public admin = makeAddr("admin");
    address public supplier = makeAddr("supplier");
    address public manufacturer = makeAddr("manufacturer");

    uint256 constant PRICE = 1000 * 1e6; // 1000 USDC
    uint256 constant MATERIAL_ID = 1;
    uint256 constant SHIPMENT_ID = 0;

    // GPS Constants
    int256 constant DEST_LAT = 40_712800;
    int256 constant DEST_LONG = -74_006000;
    uint256 constant RADIUS = 1000;

    function setUp() public {
        vm.startPrank(admin);

        // 1. Deploy Infrastructure
        usdc = new MockUSDC();
        productNft = new MockProductNft();
        functionsRouter = new MockRouter();

        // 2. Deploy Supply Chain
        supplyChain =
            new SupplyChainRWA("uri", address(productNft), address(functionsRouter), 1, 300000, bytes32("don-id"));
        supplyChain.grantRole(supplyChain.SUPPLIER_ROLE(), supplier);
        supplyChain.grantRole(supplyChain.MANUFACTURER_ROLE(), manufacturer);

        // 3. Deploy Escrow
        escrow = new PaymentEscrow(address(supplyChain), address(usdc));

        vm.stopPrank();

        // 4. Setup Tokens
        usdc.mint(manufacturer, 100_000 * 1e6); // Manufacturer has funds

        vm.prank(supplier);
        supplyChain.mint(supplier, MATERIAL_ID, 500, ""); // Supplier has goods
    }

    /*//////////////////////////////////////////////////////////////
                        HAPPY PATH SCENARIOS
    //////////////////////////////////////////////////////////////*/

    function test_Escrow_FullCycle_ShipmentArrives() public {
        // 1. Setup Shipment
        _createShipmentHelper();

        // 2. Manufacturer Funds Escrow
        vm.startPrank(manufacturer);
        usdc.approve(address(escrow), PRICE);
        escrow.createEscrow(SHIPMENT_ID, supplier, PRICE);
        vm.stopPrank();

        // Check: Funds locked
        assertEq(usdc.balanceOf(address(escrow)), PRICE);

        // 3. Supplier Ships -> Arrives
        _arriveShipmentHelper(SHIPMENT_ID);

        // 4. Manufacturer Releases Payment
        vm.prank(manufacturer);
        escrow.releasePayment(SHIPMENT_ID);

        // Check: Supplier got paid
        assertEq(usdc.balanceOf(supplier), PRICE);
        assertEq(usdc.balanceOf(address(escrow)), 0);

        // Check State
        (,, uint256 amount, bool isFunded, bool isReleased, bool isRefunded) = escrow.escrowDetails(SHIPMENT_ID);
        assertTrue(isReleased);
        assertFalse(isRefunded);
    }

    function test_Escrow_Refund_IfShipmentFails() public {
        // 1. Setup Shipment
        _createShipmentHelper();

        // 2. Fund Escrow
        vm.startPrank(manufacturer);
        usdc.approve(address(escrow), PRICE);
        escrow.createEscrow(SHIPMENT_ID, supplier, PRICE);
        vm.stopPrank();

        // 3. Manufacturer decides to cancel/refund BEFORE arrival
        // (Assuming logic allows refund if not arrived, or if strict, requires cancellation flow.
        // Based on your contract: `refundEscrow` checks `status != 2 (ARRIVED)`)

        vm.prank(manufacturer);
        escrow.refundEscrow(SHIPMENT_ID);

        // Check: Manufacturer got money back
        assertEq(usdc.balanceOf(manufacturer), 100_000 * 1e6);
        assertEq(usdc.balanceOf(address(escrow)), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        SECURITY & EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_RevertIf_ReleaseBeforeArrival() public {
        _createShipmentHelper();

        vm.startPrank(manufacturer);
        usdc.approve(address(escrow), PRICE);
        escrow.createEscrow(SHIPMENT_ID, supplier, PRICE);

        // Try to release immediately
        vm.expectRevert(PaymentEscrow.PaymentEscrow__ShipmentNotArrived.selector);
        escrow.releasePayment(SHIPMENT_ID);
        vm.stopPrank();
    }

    function test_RevertIf_RefundAfterArrival() public {
        _createShipmentHelper();

        // Fund
        vm.startPrank(manufacturer);
        usdc.approve(address(escrow), PRICE);
        escrow.createEscrow(SHIPMENT_ID, supplier, PRICE);
        vm.stopPrank();

        // Arrive
        _arriveShipmentHelper(SHIPMENT_ID);

        // Try to refund (Scam attempt by Manufacturer)
        vm.prank(manufacturer);
        vm.expectRevert(PaymentEscrow.PaymentEscrow__ShipmentAlreadyArrived.selector);
        escrow.refundEscrow(SHIPMENT_ID);
    }

    function test_RevertIf_DoubleRelease() public {
        _createShipmentHelper();

        // Fund
        vm.startPrank(manufacturer);
        usdc.approve(address(escrow), PRICE);
        escrow.createEscrow(SHIPMENT_ID, supplier, PRICE);
        vm.stopPrank();

        // Arrive
        _arriveShipmentHelper(SHIPMENT_ID);

        // First Release
        vm.prank(manufacturer);
        escrow.releasePayment(SHIPMENT_ID);

        // Second Release Attempt
        vm.prank(manufacturer);
        vm.expectRevert(PaymentEscrow.PaymentEscrow__EscrowAlreadyReleasedOrRefunded.selector);
        escrow.releasePayment(SHIPMENT_ID);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function _createShipmentHelper() internal {
        vm.startPrank(supplier);
        supplyChain.setApprovalForAll(address(supplyChain), true);
        supplyChain.createShipment(
            DEST_LAT, DEST_LONG, RADIUS, manufacturer, MATERIAL_ID, 10, block.timestamp + 2 hours
        );
        supplyChain.startDelivery(SHIPMENT_ID);
        vm.stopPrank();
    }

    function _arriveShipmentHelper(uint256 id) internal {
        // Fast forward
        vm.warp(block.timestamp + 3 hours);

        // Check Upkeep
        (, bytes memory performData) = supplyChain.checkUpkeep("");

        // Perform Upkeep -> Capture Request
        vm.recordLogs();
        supplyChain.performUpkeep(performData);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[0].topics[1];

        // Fulfill via Router Impersonation
        bytes memory response = abi.encode(DEST_LAT, DEST_LONG);
        vm.prank(address(functionsRouter));
        supplyChain.handleOracleFulfillment(requestId, response, bytes(""));
    }
}
