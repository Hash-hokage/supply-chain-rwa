// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2, Vm} from "forge-std/Test.sol";
import {SupplyChainRWA} from "src/SupplyChainRWA.sol";
import {MockRouter} from "test/mocks/MockRouter.sol";
import {MockProductNft} from "test/mocks/MockProductNft.sol";

contract SupplyChainUnit is Test {
    SupplyChainRWA public supplyChain;
    MockProductNft public productNft;
    MockRouter public functionsRouter;

    address public admin = makeAddr("admin");
    address public supplier = makeAddr("supplier");
    address public manufacturer = makeAddr("manufacturer");
    address public unauthorized = makeAddr("unauthorized");

    function setUp() public {
        vm.startPrank(admin);
        productNft = new MockProductNft();
        functionsRouter = new MockRouter();

        supplyChain = new SupplyChainRWA(
            "https://api.scm.com/",
            address(productNft),
            address(functionsRouter),
            1,
            300000,
            bytes32("don-id")
        );
        supplyChain.grantRole(supplyChain.SUPPLIER_ROLE(), supplier);
        supplyChain.grantRole(supplyChain.MANUFACTURER_ROLE(), manufacturer);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        ACCESS CONTROL UNIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_AccessControl_Mint_RevertIfUnauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert(); // AccessControl revert
        supplyChain.mint(unauthorized, 1, 100, "");
    }

    function test_AccessControl_CreateShipment_RevertIfManufacturer() public {
        vm.prank(manufacturer); // Manufacturer cannot create shipments, only Suppliers
        vm.expectRevert();
        supplyChain.createShipment(0, 0, 100, manufacturer, 1, 10, block.timestamp + 2 hours);
    }

    /*//////////////////////////////////////////////////////////////
                        INPUT VALIDATION UNIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Validation_RadiusTooSmall() public {
        vm.startPrank(supplier);
        supplyChain.mint(supplier, 1, 100, "");
        supplyChain.setApprovalForAll(address(supplyChain), true);

        vm.expectRevert(SupplyChainRWA.InvalidRadius.selector);
        supplyChain.createShipment(
            40000000, 
            -74000000, 
            49, // Radius < 50
            manufacturer, 
            1, 
            10, 
            block.timestamp + 2 hours
        );
        vm.stopPrank();
    }

    function test_Validation_ETA_TooShort() public {
        vm.startPrank(supplier);
        supplyChain.mint(supplier, 1, 100, "");
        supplyChain.setApprovalForAll(address(supplyChain), true);

        // ETA < 1 hour delay
        vm.expectRevert(SupplyChainRWA.InvalidETA.selector);
        supplyChain.createShipment(
            40000000, 
            -74000000, 
            100, 
            manufacturer, 
            1, 
            10, 
            block.timestamp + 30 minutes
        );
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        METADATA UNIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Metadata_Structure() public {
        // Setup a fake finished product state to test metadata generation
        // This requires mocking the internal state or going through the full flow.
        // For unit tests, we'll do a quick flow.
        
        // 1. Full Flow Short Circuit
        _quickShipAndAssemble();

        // 2. Check Metadata
        // Product ID 0 should exist
        string memory json = supplyChain.buildMetadata(0);
        
        console2.log(json);

        // Assertions (Primitive string containment checks)
        assertTrue(_contains("Product #0", json));
    assertTrue(_contains("Raw Material", json));
    assertTrue(_contains("Shipment ID", json));
    }

    // Helper for strings
    function _contains(string memory what, string memory where) internal pure returns (bool) {
        bytes memory whatBytes = bytes(what);
        bytes memory whereBytes = bytes(where);

        if (whatBytes.length == 0) return true;
        if (whereBytes.length < whatBytes.length) return false;

        bytes32 whatHash = keccak256(whatBytes);

        for (uint i = 0; i <= whereBytes.length - whatBytes.length; i++) {
            bytes memory sub = new bytes(whatBytes.length);
            for (uint j = 0; j < whatBytes.length; j++) {
                sub[j] = whereBytes[i + j];
            }
            if (keccak256(sub) == whatHash) {
                return true;
            }
        }
        return false;
    }

    function _quickShipAndAssemble() internal {
        vm.startPrank(supplier);
        supplyChain.mint(supplier, 1, 100, "");
        supplyChain.setApprovalForAll(address(supplyChain), true);
        supplyChain.createShipment(0, 0, 1000, manufacturer, 1, 10, block.timestamp + 2 hours);
        supplyChain.startDelivery(0);
        vm.stopPrank();

        vm.prank(admin);
        supplyChain.forceArrival(0); // Admin shortcut for unit testing metadata

        string[] memory uris = new string[](10);
        vm.prank(manufacturer);
        supplyChain.assembleProduct(0, uris);
    }
}