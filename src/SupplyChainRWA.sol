// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {
    AutomationCompatibleInterface
} from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";

import {IProductNft} from "src/IProduct.sol";

/**
 * @title SupplyChainRWA
 * @notice Real-World Asset supply chain orchestrator with Chainlink Automation + Functions integration.
 * @dev Tracks raw material shipments (ERC1155), verifies delivery via IoT oracle, releases assets on arrival,
 *      and enables manufacturers to assemble final products (ERC721).
 */
contract SupplyChainRWA is
    ERC1155,
    AccessControl,
    ERC1155Holder,
    ReentrancyGuard,
    AutomationCompatibleInterface,
    FunctionsClient
{
    using FunctionsRequest for FunctionsRequest.Request;
    using Strings for uint256;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error ShipmentNotInTransit();
    error ShipmentNotCreated();
    error ShipmentNotArrived();
    error UpkeepAlreadyInProgress();
    error TooManyActiveShipments();
    error TooManyMaterials();
    error InvalidETA();
    error InvalidRadius();
    error UnauthorizedManufacturer();
    error ShipmentAlreadyConsumed();
    error ForceArrivalTooEarly();
    error InvalidInput();

    /*//////////////////////////////////////////////////////////////
                                 ROLES
    //////////////////////////////////////////////////////////////*/
    bytes32 public constant SUPPLIER_ROLE = keccak256("SUPPLIER_ROLE");
    bytes32 public constant MANUFACTURER_ROLE = keccak256("MANUFACTURER_ROLE");

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/
    uint256 public constant MIN_ETA_DELAY = 1 hours;
    uint256 public constant MAX_ETA_DELAY = 90 days;
    uint256 public constant MAX_CONCURRENT_SHIPMENTS = 500;
    uint256 public constant MAX_MATERIALS_PER_PRODUCT = 10;
    uint256 public constant GPS_CHECK_COOLDOWN = 15 minutes;
    uint256 public constant FORCE_ARRIVAL_DELAY = 24 hours;
    uint8 public constant MAX_GPS_CHECKS = 5;

    /*//////////////////////////////////////////////////////////////
                       CHAINLINK FUNCTIONS STATE
    //////////////////////////////////////////////////////////////*/
    uint64 public subscriptionId;
    uint32 public gasLimit;
    bytes32 public donId;

    /*//////////////////////////////////////////////////////////////
                          SHIPMENT STATE
    //////////////////////////////////////////////////////////////*/
    enum ShipmentStatus {
        CREATED,
        IN_TRANSIT,
        ARRIVED
    }

    struct Shipment {
        int256 destLat; // x 1e6
        int256 destLong; // x 1e6
        uint256 radius; // meters
        address manufacturer;
        uint256 rawMaterialId;
        uint256 amount;
        ShipmentStatus status;
        uint256 expectedArrivalTime;
        uint8 gpsChecksPerformed;
        uint256 lastGpsCheckTimestamp;
    }

    mapping(uint256 => Shipment) public shipments;
    uint256 public shipmentCounter;

    // Active list for scalable Chainlink Automation
    uint256[] private activeInTransitShipments;
    mapping(uint256 => uint256) private shipmentIndexInActiveArray; // shipmentId → index+1

    // Upkeep protection
    mapping(uint256 => bool) public pendingUpkeep;

    // Chainlink Functions request tracking
    mapping(bytes32 => uint256) public requestIdToShipment;

    /*//////////////////////////////////////////////////////////////
                          MANUFACTURING STATE
    //////////////////////////////////////////////////////////////*/
    mapping(uint256 => uint256) public productToShipment;
    mapping(uint256 => uint256[MAX_MATERIALS_PER_PRODUCT]) public productRawMaterials;
    mapping(uint256 => uint8) public productMaterialCount;
    mapping(uint256 => uint256) public productAssemblyTimestamp;
    mapping(uint256 => bool) public shipmentConsumed;

    IProductNft public immutable productNft;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event ShipmentCreated(uint256 indexed shipmentId, address indexed manufacturer, uint256 expectedArrivalTime);
    event ShipmentArrived(uint256 indexed shipmentId, address indexed manufacturer);
    event ProductAssembled(uint256 indexed shipmentId, address indexed manufacturer, uint256 quantity);
    event OracleRequestFailed(uint256 indexed shipmentId, bytes error);
    event ForceArrival(uint256 indexed shipmentId, address indexed caller);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(
        string memory uri,
        address _productNft,
        address _functionsRouter,
        uint64 _subscriptionId,
        uint32 _gasLimit,
        bytes32 _donId
    ) ERC1155(uri) FunctionsClient(_functionsRouter) {
        productNft = IProductNft(_productNft);

        subscriptionId = _subscriptionId;
        gasLimit = _gasLimit;
        donId = _donId;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                          SUPPLIER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function mint(address to, uint256 id, uint256 amount, bytes memory data) external onlyRole(SUPPLIER_ROLE) {
        _mint(to, id, amount, data);
    }

    /**
     * @notice Supplier locks raw materials and creates a shipment.
     */
    function createShipment(
        int256 destLat,
        int256 destLong,
        uint256 radius,
        address manufacturer,
        uint256 rawMaterialId,
        uint256 amount,
        uint256 expectedArrivalTime
    ) external onlyRole(SUPPLIER_ROLE) nonReentrant {
        if (
            expectedArrivalTime < block.timestamp + MIN_ETA_DELAY
                || expectedArrivalTime > block.timestamp + MAX_ETA_DELAY
        ) {
            revert InvalidETA();
        }
        if (radius < 50 || radius > 10_000) revert InvalidRadius();

        safeTransferFrom(msg.sender, address(this), rawMaterialId, amount, "");

        uint256 shipmentId = shipmentCounter++;
        shipments[shipmentId] = Shipment({
            destLat: destLat,
            destLong: destLong,
            radius: radius,
            manufacturer: manufacturer,
            rawMaterialId: rawMaterialId,
            amount: amount,
            status: ShipmentStatus.CREATED,
            expectedArrivalTime: expectedArrivalTime,
            gpsChecksPerformed: 0,
            lastGpsCheckTimestamp: 0
        });

        emit ShipmentCreated(shipmentId, manufacturer, expectedArrivalTime);
    }

    /**
     * @notice Supplier marks shipment as picked up and in transit.
     */
    function startDelivery(uint256 shipmentId) external onlyRole(SUPPLIER_ROLE) {
        Shipment storage s = shipments[shipmentId];
        if (s.status != ShipmentStatus.CREATED) revert ShipmentNotCreated();

        s.status = ShipmentStatus.IN_TRANSIT;
        _addToActiveList(shipmentId);
    }

    /*//////////////////////////////////////////////////////////////
                     CHAINLINK AUTOMATION + FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
        for (uint256 i = 0; i < activeInTransitShipments.length; i++) {
            uint256 id = activeInTransitShipments[i];
            Shipment memory s = shipments[id];

            if (
                s.status == ShipmentStatus.IN_TRANSIT && block.timestamp >= s.expectedArrivalTime
                    && s.gpsChecksPerformed < MAX_GPS_CHECKS
                    && (s.lastGpsCheckTimestamp == 0 || block.timestamp >= s.lastGpsCheckTimestamp + GPS_CHECK_COOLDOWN)
            ) {
                return (true, abi.encode(id));
            }
        }
        return (false, "");
    }

    function performUpkeep(bytes calldata performData) external override {
        uint256 shipmentId = abi.decode(performData, (uint256));
        Shipment storage s = shipments[shipmentId];

        if (pendingUpkeep[shipmentId]) revert UpkeepAlreadyInProgress();
        pendingUpkeep[shipmentId] = true;

        s.gpsChecksPerformed += 1;
        s.lastGpsCheckTimestamp = block.timestamp;

        string memory source =
            "const lat = response.data.latitude; const long = response.data.longitude; return Functions.encodeInt256(lat).concat(Functions.encodeInt256(long));";

        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source);

        string[] memory args = new string[](1);
        args[0] = shipmentId.toString();
        req.setArgs(args);

        bytes32 requestId = _sendRequest(req.encodeCBOR(), subscriptionId, gasLimit, donId);
        requestIdToShipment[requestId] = shipmentId;
    }

    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) internal override {
        uint256 shipmentId = requestIdToShipment[requestId];
        delete requestIdToShipment[requestId];

        if (err.length > 0) {
            emit OracleRequestFailed(shipmentId, err);
            return;
        }

        delete pendingUpkeep[shipmentId];

        (int256 lat, int256 lng) = abi.decode(response, (int256, int256));
        Shipment storage s = shipments[shipmentId];

        int256 dLat = lat - s.destLat;
        int256 dLng = lng - s.destLong;
        uint256 distanceSq = uint256((dLng * dLng) + (dLat * dLat));

        if (distanceSq <= s.radius * s.radius) {
            _completeArrival(shipmentId, s);
        }
    }

    /*//////////////////////////////////////////////////////////////
                          FORCE ARRIVAL
    //////////////////////////////////////////////////////////////*/
    function manufacturerForceArrival(uint256 shipmentId) external {
        Shipment storage s = shipments[shipmentId];
        if (s.status != ShipmentStatus.IN_TRANSIT) revert ShipmentNotInTransit();
        if (msg.sender != s.manufacturer) revert UnauthorizedManufacturer();
        if (block.timestamp < s.expectedArrivalTime + FORCE_ARRIVAL_DELAY) revert ForceArrivalTooEarly();

        _completeArrival(shipmentId, s);
    }

    function forceArrival(uint256 shipmentId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Shipment storage s = shipments[shipmentId];
        if (s.status != ShipmentStatus.IN_TRANSIT) revert ShipmentNotInTransit();
        _completeArrival(shipmentId, s);
    }

    function _completeArrival(uint256 shipmentId, Shipment storage s) internal {
        s.status = ShipmentStatus.ARRIVED;
        _removeFromActiveList(shipmentId);
        delete pendingUpkeep[shipmentId];

        _safeTransferFrom(address(this), s.manufacturer, s.rawMaterialId, s.amount, "");

        emit ShipmentArrived(shipmentId, s.manufacturer);
        emit ForceArrival(shipmentId, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                          MANUFACTURING
    //////////////////////////////////////////////////////////////*/
    modifier onlyArrived(uint256 shipmentId) {
        if (shipments[shipmentId].status != ShipmentStatus.ARRIVED) revert ShipmentNotArrived();
        _;
    }

    function assembleProduct(uint256 shipmentId, string[] calldata metadataURIs)
        external
        onlyRole(MANUFACTURER_ROLE)
        onlyArrived(shipmentId)
        nonReentrant
    {
        Shipment memory s = shipments[shipmentId];
        if (msg.sender != s.manufacturer) revert UnauthorizedManufacturer();
        if (shipmentConsumed[shipmentId]) revert ShipmentAlreadyConsumed();
        if (balanceOf(msg.sender, s.rawMaterialId) < s.amount) {
            revert ERC1155InsufficientBalance(
                msg.sender, s.amount, balanceOf(msg.sender, s.rawMaterialId), s.rawMaterialId
            );
        }
        if (metadataURIs.length != s.amount) revert InvalidInput();

        shipmentConsumed[shipmentId] = true;
        _burn(msg.sender, s.rawMaterialId, s.amount);

        for (uint256 i = 0; i < s.amount; i++) {
            uint256 productId = productNft.mintProductNft(msg.sender, metadataURIs[i]);

            productToShipment[productId] = shipmentId;
            productAssemblyTimestamp[productId] = block.timestamp;

            uint8 count = productMaterialCount[productId];
            if (count >= MAX_MATERIALS_PER_PRODUCT) revert TooManyMaterials();
            productRawMaterials[productId][count] = s.rawMaterialId;
            productMaterialCount[productId] = count + 1;
        }

        emit ProductAssembled(shipmentId, msg.sender, s.amount);
    }

    /*//////////////////////////////////////////////////////////////
                             METADATA
    //////////////////////////////////////////////////////////////*/
    function buildMetadata(uint256 productId) external view returns (string memory) {
        uint256 shipmentId = productToShipment[productId];
        uint256 assembledAt = productAssemblyTimestamp[productId];
        Shipment memory s = shipments[shipmentId];

        string memory materialAttrs = "";
        uint8 count = productMaterialCount[productId];
        for (uint8 i = 0; i < count; i++) {
            if (i > 0) materialAttrs = string(abi.encodePacked(materialAttrs, ","));
            materialAttrs = string(
                abi.encodePacked(
                    materialAttrs,
                    '{"trait_type":"Raw Material ',
                    Strings.toString(i + 1),
                    ' ID","value":"',
                    Strings.toString(productRawMaterials[productId][i]),
                    '"}'
                )
            );
        }
        if (count == 0) materialAttrs = '{"trait_type":"Raw Material","value":"Unknown"}';

        string memory attrs = string(
            abi.encodePacked(
                '{"trait_type":"Shipment ID","value":"',
                Strings.toString(shipmentId),
                '"},',
                materialAttrs,
                ',{"trait_type":"Manufacturer","value":"',
                _addressToString(s.manufacturer),
                '"},',
                '{"trait_type":"Assembled At","value":"',
                Strings.toString(assembledAt),
                '"}'
            )
        );

        return string(
            abi.encodePacked(
                '{"name":"Product #',
                Strings.toString(productId),
                '","description":"Assembled from shipment #',
                Strings.toString(shipmentId),
                " by ",
                _addressToString(s.manufacturer),
                " on ",
                Strings.toString(assembledAt),
                '","attributes":[',
                attrs,
                "]}"
            )
        );
    }

    function getShipmentStatus(uint256 shipmentId) external view returns (uint8) {
        return uint8(shipments[shipmentId].status);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/
    function _addToActiveList(uint256 shipmentId) internal {
        if (activeInTransitShipments.length >= MAX_CONCURRENT_SHIPMENTS) revert TooManyActiveShipments();
        activeInTransitShipments.push(shipmentId);
        shipmentIndexInActiveArray[shipmentId] = activeInTransitShipments.length;
    }

    function _removeFromActiveList(uint256 shipmentId) internal {
        uint256 index = shipmentIndexInActiveArray[shipmentId] - 1;
        if (index >= activeInTransitShipments.length) return;

        uint256 lastId = activeInTransitShipments[activeInTransitShipments.length - 1];
        activeInTransitShipments[index] = lastId;
        shipmentIndexInActiveArray[lastId] = index + 1;

        activeInTransitShipments.pop();
        delete shipmentIndexInActiveArray[shipmentId];
    }

    function _addressToString(address addr) internal pure returns (string memory) {
        return addr == address(0) ? "0x0000000000000000000000000000000000000000" : Strings.toHexString(addr);
    }

    /*//////////////////////////////////////////////////////////////
                             INTERFACE
    //////////////////////////////////////////////////////////////*/
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, AccessControl, ERC1155Holder)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
