// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {SupplyChainRWA} from "src/SupplyChainRWA.sol";
import {ProductNft} from "src/ProductNft.sol";
import {MockRouter} from "test/mocks/MockRouter.sol";
import {HelperConfig} from "script/HelperConfig.s.sol"; // Assumed path

/// @title SupplyChainRWA Integration Tests
/// @author Hash-Hokage
/// @notice Integration tests focusing on the manufacturing and assembly logic.
/// @dev Validates state transitions between raw material acquisition, shipment, and product assembly.
contract SupplyChainRWAIntegrationTest is Test {
    
    // ================================================================
    // │                            STATE                             │
    // ================================================================

    SupplyChainRWA private supplyChain;
    ProductNft private productNft;
    HelperConfig private helperConfig;
    MockRouter private mockRouter; // Kept for local simulation

    address private supplier = makeAddr("supplier");
    address private manufacturer = makeAddr("manufacturer");
    address private router;
    
    uint64 private subId;
    uint32 private gasLimit;
    bytes32 private donId;

    uint256 private constant RAW_ID = 1;
    uint256 private constant SHIPMENT_RADIUS = 1000;

    // ================================================================
    // │                            SETUP                             │
    // ================================================================

    function setUp() public {
        // 1. Load Configuration
        helperConfig = new HelperConfig();
        
        // DESTUCTURING FIX:
        // We must match the NetworkConfig struct order: 
        // (address router, address linkToken, bytes32 donId, uint64 subId)
        (
            address _router,
            address _linkToken,
            bytes32 _donId,
            uint64 _subId
        ) = helperConfig.activeNetworkConfig();

        router = _router;
        subId = _subId;
        donId = _donId;
        
        // Since gasLimit is not in your HelperConfig struct, we define a default here
        gasLimit = 300000; 
        
        // We aren't using _linkToken in the test state variables, so we just ignore it for now
        // or you can add `address linkToken` to your state variables if needed.

        // 2. Deploy Contracts
        // We assume the router in config might be real, but for this integration test
        // we generally need the mock to control the responses.
        mockRouter = new MockRouter(); 

        productNft = new ProductNft(address(this));
        
        supplyChain = new SupplyChainRWA(
            "ipfs://base-uri", 
            address(productNft), 
            address(mockRouter), 
            subId, 
            gasLimit, 
            donId
        );

        // 3. Role Assignment
        vm.startPrank(address(this)); 
        supplyChain.grantRole(supplyChain.SUPPLIER_ROLE(), supplier);
        supplyChain.grantRole(supplyChain.MANUFACTURER_ROLE(), manufacturer);
        vm.stopPrank();
    }

    // ================================================================
    // │                           HELPERS                            │
    // ================================================================

    /// @dev Mints raw material tokens and approves the SupplyChain contract.
    function _mintRawMaterials(uint256 amount) internal {
        vm.startPrank(supplier);
        supplyChain.mint(supplier, RAW_ID, amount, "");
        supplyChain.setApprovalForAll(address(supplyChain), true);
        vm.stopPrank();
    }

    /// @dev Creates a shipment fixture with standard test parameters.
    function _createShipmentFixture(uint256 amount) internal returns (uint256 shipmentId) {
        vm.startPrank(supplier);
        supplyChain.createShipment(
            0, 
            0, 
            SHIPMENT_RADIUS, 
            manufacturer, 
            RAW_ID, 
            amount, 
            block.timestamp + 1 days, 
            0
        );
        vm.stopPrank();
        return 0; // First shipment ID is always 0 in isolated test env
    }

    /// @dev Simulates the Chainlink Functions workflow (Request -> Fulfillment).
    function _triggerShipmentArrival(uint256 shipmentId) internal {
        // 1. Initiate Delivery
        vm.prank(supplier);
        supplyChain.startDelivery(shipmentId);

        // 2. Time Travel
        vm.warp(block.timestamp + 1 days + 1);

        // 3. Mock Router Request
        bytes32 requestId = bytes32("req_integration");
        vm.mockCall(
            address(mockRouter),
            abi.encodeWithSignature("sendRequest(uint64,bytes,uint16,uint32,bytes32)"),
            abi.encode(requestId)
        );

        // 4. Perform Upkeep (Trigger Chainlink Call)
        supplyChain.performUpkeep(abi.encode(shipmentId));

        // 5. Mock Router Fulfillment
        // Coordinates (0,0) are within the defined radius of 1000
        bytes memory response = abi.encode(int256(0), int256(0), uint256(1)); 
        bytes memory err = "";

        vm.prank(address(mockRouter));
        supplyChain.handleOracleFulfillment(requestId, response, err);
    }

    // ================================================================
    // │                            TESTS                             │
    // ================================================================

    function test_Integration_FullLifecycle_Succeeds() public {
        uint256 amount = 2;

        // Arrange
        _mintRawMaterials(amount);
        uint256 shipmentId = _createShipmentFixture(amount);

        // Act: Arrival
        _triggerShipmentArrival(shipmentId);

        // Assert: Escrow Release
        assertEq(supplyChain.balanceOf(manufacturer, RAW_ID), amount, "Manufacturer should receive raw materials");

        // Prepare Metadata
        string[] memory metadataURIs = new string[](amount);
        metadataURIs[0] = "ipfs://meta-0";
        metadataURIs[1] = "ipfs://meta-1";

        // Assert: Events
        vm.expectEmit(true, true, true, true);
        emit SupplyChainRWA.ProductAssembled(shipmentId, manufacturer, amount);

        // Act: Assembly (with Gas Profiling)
        uint256 gasStart = gasleft();
        
        vm.prank(manufacturer);
        supplyChain.assembleProduct(shipmentId, metadataURIs);
        
        uint256 gasUsed = gasStart - gasleft();
        console.log("Gas used for assembleProduct (Integration):", gasUsed);

        // Assert: Final State
        assertEq(supplyChain.balanceOf(manufacturer, RAW_ID), 0, "Raw materials should be burned");
        assertEq(productNft.balanceOf(manufacturer), amount, "Manufacturer should own Product NFTs");
        
        // Assert: Mappings
        assertEq(supplyChain.productToShipment(0), shipmentId, "Product 0 ID mapping incorrect");
        assertEq(supplyChain.productToShipment(1), shipmentId, "Product 1 ID mapping incorrect");
    }

    function test_Revert_If_UnauthorizedManufacturer() public {
        // Arrange
        _mintRawMaterials(1);
        uint256 shipmentId = _createShipmentFixture(1);
        _triggerShipmentArrival(shipmentId);

        address attacker = makeAddr("attacker");
        supplyChain.grantRole(supplyChain.MANUFACTURER_ROLE(), attacker);

        string[] memory metadataURIs = new string[](1);
        metadataURIs[0] = "ipfs://meta";

        // Act & Assert
        vm.prank(attacker);
        vm.expectRevert(bytes("Not authorized manufacturer"));
        supplyChain.assembleProduct(shipmentId, metadataURIs);
    }

    function test_Revert_If_ShipmentNotArrived() public {
        // Arrange
        _mintRawMaterials(1);
        _createShipmentFixture(1); // Do not trigger arrival

        string[] memory metadataURIs = new string[](1);
        metadataURIs[0] = "ipfs://meta";

        // Act & Assert
        vm.prank(manufacturer);
        vm.expectRevert(bytes("Shipment not arrived"));
        supplyChain.assembleProduct(0, metadataURIs);
    }

    function test_Revert_If_InsufficientRawMaterials() public {
        // Arrange
        uint256 amount = 2;
        _mintRawMaterials(amount);
        uint256 shipmentId = _createShipmentFixture(amount);
        _triggerShipmentArrival(shipmentId);

        // Simulate manufacturer losing/selling one raw material token
        vm.prank(manufacturer);
        supplyChain.safeTransferFrom(manufacturer, address(0xdead), RAW_ID, 1, "");

        string[] memory metadataURIs = new string[](2); // Intending to build 2 products
        metadataURIs[0] = "ipfs://meta0";
        metadataURIs[1] = "ipfs://meta1";

        // Act & Assert
        vm.prank(manufacturer);
        vm.expectRevert(bytes("Not enough raw materials"));
        supplyChain.assembleProduct(shipmentId, metadataURIs);
    }

    function test_Revert_If_MetadataCountMismatch() public {
        // Arrange
        uint256 amount = 2;
        _mintRawMaterials(amount);
        uint256 shipmentId = _createShipmentFixture(amount);
        _triggerShipmentArrival(shipmentId);

        string[] memory metadataURIs = new string[](1); // Mismatch: 1 URI for 2 Items
        metadataURIs[0] = "ipfs://only-one";

        // Act & Assert
        vm.prank(manufacturer);
        vm.expectRevert(bytes("Metadata list must match raw material amount"));
        supplyChain.assembleProduct(shipmentId, metadataURIs);
    }

    function test_Revert_If_ShipmentAlreadyUsed() public {
        // Arrange
        _mintRawMaterials(1);
        uint256 shipmentId = _createShipmentFixture(1);
        _triggerShipmentArrival(shipmentId);

        string[] memory metadataURIs = new string[](1);
        metadataURIs[0] = "ipfs://first";

        // Act 1: Successful Assembly
        vm.prank(manufacturer);
        supplyChain.assembleProduct(shipmentId, metadataURIs);

        // Act 2 & Assert: Replay Attack
        vm.prank(manufacturer);
        vm.expectRevert(bytes("Shipment already used"));
        supplyChain.assembleProduct(shipmentId, metadataURIs);
    }
}