//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

 /*//////////////////////////////////////////////////////////////
                                IMPORTS
 //////////////////////////////////////////////////////////////*/

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {
    AutomationCompatibleInterface
} from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";

/** 
* @title RWA Supply Chain Orchestrator
* @author Omisade Olamiposi
* @notice Manages the life cycle of Real World Assets(RWA) from raw material sourcing to final delivery.
* @dev Implements a hybrid Chainlink architecture:
*       1. Automation: Monitors shipments in transit.
*       2. Functions(planned): Verifies IoT GPS/Temprature data before state transitions.
*       3. ERC1155: Represents batch raw materials.
*/

contract SupplyChainRWA is ERC1155, AccessControl, ERC1155Holder, AutomationCompatibleInterface {

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when an operation is attempted on a shipment not currently moving.    
    error SupplyChainRWA__shipmentNotInTransit();
    /// @notice Thrown when an operation is attempted on a shipment that has not been created.
    error SupplyChainRWA__shipmentNotCreated();

     /*//////////////////////////////////////////////////////////////
                                 ROLES
    //////////////////////////////////////////////////////////////*/

    /// @dev roles for entities that transform raw materials.
    bytes32 public constant MANUFACTURER_ROLE = keccak256("MANUFACTURER_ROLE");
    /// @dev roles for entities that supply raw materials.
    bytes32 public constant SUPPLIER_ROLE = keccak256("SUPPLIER_ROLE");

    /*//////////////////////////////////////////////////////////////
                              STATE & TYPES
    //////////////////////////////////////////////////////////////*/
    enum ShipmentStatus {
        CREATED, // Material locked and ready ready for pickup or transportation.
        IN_TRANSIT, // En Route to destination.
        ARRIVED // Arrived at destination.
    }


    /// @notice Defines the parameters of a physical shipment.
    /// @dev Uses int256 for coordinates to handle negative values (South/West).
    struct Shipment {
        // --- Geospatial Data ---
        int256 destLat; // Latitude (multiplied by 10^6 for precision).
        int256 destLong; // Longitude (multiplied by 10^6 for precision).
        uint256 radius; // accepted delivery raduis in meters.

        // --- Asset Data ---
        address manufacturer; // The Intended receipient.
        uint256 rawMaterialId; // The ERC1155 token Id.
        uint256 amount; // quantity of token 

        // --- System State ---
        ShipmentStatus status;
    }

    /// @notice Registry of all shipments tracked by the protocol.
    mapping(uint256 => Shipment) public shipments;

    /// @notice Counter to generate unique Shipment IDs.
    uint256 public shipmentCounter;


    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets up the governance roles.
    /// @param uri The metadata URI for the ERC1155 tokens.
    constructor(string memory uri) ERC1155(uri) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /** 
    * @notice Mints new raw material tokens.
    * @dev Only callable by verified Suppliers.
    * @param account The address receiving the tokens.
    * @param id The token ID type.
    * @param amount The quantity to mint.
    * @param data Additional data for hooks
    */
     function mint(address account, uint256 id, uint256 amount, bytes memory data) public onlyRole(SUPPLIER_ROLE) {
        _mint(account, id, amount, data);
    }

    /** 
    * @notice Locks raw materials and initializes a shipment request.
    * @dev Transfers ERC1155 tokens from Supplier to this Contract (Escrow).
    * @param destLat Destination Latitude (e.g. 6.5244 * 10^6).
    * @param destLong Destination Longitude.
    * @param radius Allowed error margin for GPS delivery.
    * @param manufacturer The address of the receiver.
    * @param rawMaterialId The token ID being shipped.
    * @param amount The quantity being shipped.
    */
    function createShipment(
        int256 destLat,
        int256 destLong,
        uint256 radius,
        address manufacturer,
        uint256 rawMaterialId,
        uint256 amount
    ) external onlyRole(SUPPLIER_ROLE) {
        // Escrow assets
        safeTransferFrom(msg.sender, address(this), rawMaterialId, amount, "");

        //Register Shipment
        shipments[shipmentCounter] = Shipment({
            destLat: destLat,
            destLong: destLong,
            radius: radius,
            manufacturer: manufacturer,
            rawMaterialId: rawMaterialId,
            amount: amount,
            status: ShipmentStatus.CREATED
        });
        shipmentCounter++;
    }

    /// @notice Marks a shipment as picked up and moving.
    /// @param shipmentId The ID of the shipment to update.
    function startDelivery(uint256 shipmentId) external onlyRole(SUPPLIER_ROLE) {
        Shipment storage shipment = shipments[shipmentId];

        if (shipment.status != ShipmentStatus.CREATED) {
            revert SupplyChainRWA__shipmentNotCreated();
        } else {
            shipment.status = ShipmentStatus.IN_TRANSIT;
        }
    }

    /*//////////////////////////////////////////////////////////////
                             AUTOMATION & IOT
    //////////////////////////////////////////////////////////////*/

    /**
    * @notice Chainlink Automation: Checks if any shipment needs an update.
    * @dev Scans open shipments. If IN_TRANSIT, triggers performUpkeep.
    * @return upkeepNeeded True if a shipment is moving.
    * @return performData Encoded ID of the shipment to check.
    */
    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        returns (
            bool upkeepNeeded,
            bytes memory /* performData */
        )
    {
        for (uint256 i = 0; i < shipmentCounter; i++) {
            Shipment storage shipment = shipments[i];

            if (shipment.status == ShipmentStatus.IN_TRANSIT) {
                upkeepNeeded = true;
                return (true, abi.encode(i));
            }
        }
        return (false, "");
    }

    /**
    * @notice Chainlink Automation: Executes the state change.
    * @dev CURRENTLY: Auto-arrives the shipment (for testing).
    * @custom:todo INTEGRATION: This function should trigger a Chainlink Function Request
    *              to verify GPS coordinates before marking as ARRIVED.
    */
    function performUpkeep(bytes calldata performData) external {
        uint256 shipmentId = abi.decode(performData, (uint256));
        Shipment storage shipment = shipments[shipmentId];

        if (shipment.status != ShipmentStatus.IN_TRANSIT) {
            revert SupplyChainRWA__shipmentNotInTransit();
        }

        // --- SIMULATED ARRIVAL (Placeholder for IoT verification) ---
        shipment.status = ShipmentStatus.ARRIVED;

        // Release assets from Escrow to Manufacturer
        _safeTransferFrom(address(this), shipment.manufacturer, shipment.rawMaterialId, shipment.amount, "");
    }

    /**
    * @notice Converts raw materials into a final product (ERC721).
    * @custom:todo Implement manufacturing logic (burn ERC1155 -> mint ERC721).
    */
    function assembleProduct() external onlyRole(MANUFACTURER_ROLE) {}

    // ==========================================
    // 🔧 OVERRIDES
    // ==========================================

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, AccessControl, ERC1155Holder)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

