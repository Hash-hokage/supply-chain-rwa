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
import {IProductNft} from "src/IProduct.sol";
import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title RWA Supply Chain Orchestrator
 * @author Omisade Olamiposi
 * @notice Manages the life cycle of Real World Assets(RWA) from raw material sourcing to final delivery.
 * @dev Implements a hybrid Chainlink architecture:
 *       1. Automation: Monitors shipments in transit.
 *       2. Functions(planned): Verifies IoT GPS/Temprature data before state transitions.
 *       3. ERC1155: Represents batch raw materials.
 */

contract SupplyChainRWA is ERC1155, AccessControl, ERC1155Holder, AutomationCompatibleInterface, FunctionsClient {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when an operation is attempted on a shipment not currently moving.
    error SupplyChainRWA__shipmentNotInTransit();
    /// @notice Thrown when an operation is attempted on a shipment that has not been created.
    error SupplyChainRWA__shipmentNotCreated();

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    using FunctionsRequest for FunctionsRequest.Request;
    using Strings for uint256;

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

        uint256 expectedArrivalTime;
        uint256 lastCheckTimestamp;
    }

    /// @notice Registry of all shipments tracked by the protocol.
    mapping(uint256 shipmentId => Shipment) public shipments;
    mapping(uint256 => uint256) public productToShipment; //This links a finished product NFT to the shipment of raw materials used.
    mapping(uint256 => uint256[]) public productToRawMaterial; //This connects a product to the raw materials used.
    mapping(bytes32 requestId => uint256 shipmentId) public requestIdToShipment;

    /// @notice Counter to generate unique Shipment IDs.
    uint256 public shipmentCounter;

    uint64 public subscriptionId;
    uint32 public gasLimit;
    bytes32 public donId;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event ShipmentArrived(uint256 shipmentId, address manufacturer);
    event ProductAssembled(uint256 shipmentId, address manufacturer, uint256 quantity);

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets up the governance roles.
    /// @param uri The metadata URI for the ERC1155 tokens.
    constructor(
        string memory uri,
        address nftAddress,
        address router,
        uint64 _subscriptionId,
        uint32 _gasLimit,
        bytes32 _donId
    ) ERC1155(uri) FunctionsClient(router) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        productNft = IProductNft(nftAddress);
        subscriptionId = _subscriptionId;
        gasLimit = _gasLimit;
        donId = _donId;
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
        uint256 amount,
        uint256 expectedArrivalTime,
        uint256 lastCheckTimestamp
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
            status: ShipmentStatus.CREATED,
            expectedArrivalTime: expectedArrivalTime,
            lastCheckTimestamp: lastCheckTimestamp
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
     * @dev Scans open shipments. If IN_TRANSIT, calculates if its in geoFence and triggers performUpkeep.
     * @return upkeepNeeded True if a shipment is moving and within geoFence.
     * @return performData Encoded ID of the shipment to check.
     */
    function checkUpkeep(
        bytes calldata /*checkData*/
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
                if (
                    (block.timestamp >= shipment.expectedArrivalTime)
                        && (block.timestamp - shipment.lastCheckTimestamp >= 30 minutes
                            || shipment.lastCheckTimestamp == 0)
                ) {
                    return (true, abi.encode(i));
                }
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
    function performUpkeep(bytes calldata performData) external override {
        // 1. Decode the Shipment ID from the checkUpkeep data
        (uint256 shipmentId) = abi.decode(performData, (uint256));

        // 2. Define the JS Source Code
        string memory source = "const lat = response.data.latitude;" "const long = response.data.longitude;"
            "const stat = response.data.status;"
            "return Buffer.concat([Functions.encodeInt256(lat), Functions.encodeInt256(long), Functions.encodeUint256(stat)]);";

        // 3. Initialize the Request
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source);

        // 4. Set Args
        string[] memory args = new string[](1);
        args[0] = shipmentId.toString();
        req.setArgs(args);

        // 5. Send the Request
        bytes32 requestId = _sendRequest(req.encodeCBOR(), subscriptionId, gasLimit, donId);

        // 6. Save the link so we know which shipment this request belongs to
        requestIdToShipment[requestId] = shipmentId;
    }

    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) internal override {
        (int256 latitude, int256 longitude, uint256 status) = abi.decode(response, (int256, int256, uint256));
        uint256 shipmentId = requestIdToShipment[requestId];
        Shipment storage shipment = shipments[shipmentId];
        require(shipment.status == ShipmentStatus.IN_TRANSIT);
        int256 diffLat = latitude - shipment.destLat;
        int256 diffLong = longitude - shipment.destLong;
        uint256 squaredDistance = uint256((diffLong * diffLong) + (diffLat * diffLat));
        if (squaredDistance <= (shipment.radius * shipment.radius)) {
            shipment.status = ShipmentStatus.ARRIVED;
            // Release assets from Escrow to Manufacturer
            _safeTransferFrom(address(this), shipment.manufacturer, shipment.rawMaterialId, shipment.amount, "");
            emit ShipmentArrived(shipmentId, shipment.manufacturer);
        }
    }

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

    /*//////////////////////////////////////////////////////////////
                               MANUFACTURING LOGIC
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Converts raw materials into a final product (ERC721).
     * @custom:todo Implement manufacturing logic (burn ERC1155 -> mint ERC721).
     *
     */

    modifier onlyArrived(uint256 shipmentId) {
        _shipmentArrived(shipmentId);
        _;
    }

    function _shipmentArrived(uint256 shipmentId) internal view {
        require(shipments[shipmentId].status == ShipmentStatus.ARRIVED, "Shipment not arrived");
    }
    //interface
    IProductNft public productNft;

    //asssemble function
    function assembleProduct(uint256 shipmentId, string[] calldata metadataURIs)
        external
        onlyRole(MANUFACTURER_ROLE)
        onlyArrived(shipmentId)
    {
        Shipment memory shipment = shipments[shipmentId];
        uint256 rawId = shipment.rawMaterialId;
        uint256 amount = shipment.amount;
        _burn(msg.sender, rawId, amount);

        for (uint256 i = 0; i < amount; i++) {
            uint256 newProductId = productNft.mintProductNft(msg.sender, metadataURIs[i]);

            productToShipment[newProductId] = shipmentId;
            productToShipment[newProductId] = shipmentId;
            productToRawMaterial[newProductId].push(shipment.rawMaterialId);
        }

        emit ProductAssembled(shipmentId, msg.sender, amount);
    }
}

