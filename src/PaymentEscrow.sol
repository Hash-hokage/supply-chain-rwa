// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISupplyChain} from "./IProduct.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract PaymentEscrow is ReentrancyGuard {
    // --- State Variables ---
    address public immutable supplyChain;
    IERC20 public immutable paymentToken;

    struct EscrowDetail {
        address manufacturer;
        address supplier;
        uint256 amount;
        bool isFunded;
        bool isReleased;
        bool isRefunded;
    }

    mapping(uint256 => EscrowDetail) public escrowDetails;

    // --- Events ---
    event EscrowCreated(uint256 indexed shipmentId, address manufacturer, address supplier, uint256 amount);
    event PaymentReleased(uint256 indexed shipmentId, address supplier, uint256 amount);
    event EscrowRefunded(uint256 indexed shipmentId, address manufacturer, uint256 amount);

    // --- Constructor ---
    constructor(address _supplyChain, address _paymentToken) {
        supplyChain = _supplyChain;
        paymentToken = IERC20(_paymentToken);
    }

    // --- Errors ---
    error PaymentEscrow__InvalidInput();
    error PaymentEscrow__TransferFailed();
    error PaymentEscrow__NotManufacturer();
    error PaymentEscrow__EscrowNotFunded();
    error PaymentEscrow__EscrowAlreadyReleasedOrRefunded();
    error PaymentEscrow__ShipmentNotArrived();
    error PaymentEscrow__ShipmentAlreadyArrived();

    // --- Functions ---

    /// @notice Locks funds for a specific shipment
    /// @param shipmentId The ID from the SupplyChain contract
    /// @param supplier The address that will eventually receive the funds
    /// @param amount The amount of tokens to lock
    function createEscrow(uint256 shipmentId, address supplier, uint256 amount) external nonReentrant {
        if (escrowDetails[shipmentId].isFunded) revert PaymentEscrow__EscrowAlreadyReleasedOrRefunded();
        if (amount == 0) revert PaymentEscrow__InvalidInput();

        bool success = paymentToken.transferFrom(msg.sender, address(this), amount);
        if (!success) revert PaymentEscrow__TransferFailed();

        escrowDetails[shipmentId] = EscrowDetail({
            manufacturer: msg.sender,
            supplier: supplier,
            amount: amount,
            isFunded: true,
            isReleased: false,
            isRefunded: false
        });

        emit EscrowCreated(shipmentId, msg.sender, supplier, amount);
    }

    /// @notice Release payment to supplier when shipment arrives
    /// @dev Only manufacturer can call (or make it public if you want anyone)
    function releasePayment(uint256 shipmentId) external nonReentrant {
        EscrowDetail storage escrow = escrowDetails[shipmentId];

        if (!escrow.isFunded) revert PaymentEscrow__EscrowNotFunded();
        if (escrow.isReleased || escrow.isRefunded) revert PaymentEscrow__EscrowAlreadyReleasedOrRefunded();
        if (msg.sender != escrow.manufacturer) revert PaymentEscrow__NotManufacturer();

        uint8 status = ISupplyChain(supplyChain).getShipmentStatus(shipmentId);
        if (status != 2) revert PaymentEscrow__ShipmentNotArrived();

        escrow.isReleased = true;

        bool success = paymentToken.transfer(escrow.supplier, escrow.amount);
        if (!success) revert PaymentEscrow__TransferFailed();

        emit PaymentReleased(shipmentId, escrow.supplier, escrow.amount);
    }

    /// @notice Refund manufacturer if supplier never ships (before arrival)
    function refundEscrow(uint256 shipmentId) external nonReentrant {
        EscrowDetail storage escrow = escrowDetails[shipmentId];

        if (!escrow.isFunded) revert PaymentEscrow__EscrowNotFunded();
        if (escrow.isReleased || escrow.isRefunded) revert PaymentEscrow__EscrowAlreadyReleasedOrRefunded();
        if (msg.sender != escrow.manufacturer) revert PaymentEscrow__NotManufacturer();

        uint8 status = ISupplyChain(supplyChain).getShipmentStatus(shipmentId);
        if (status == 2) revert PaymentEscrow__ShipmentAlreadyArrived(); // too late

        escrow.isRefunded = true;

        bool success = paymentToken.transfer(escrow.manufacturer, escrow.amount);
        if (!success) revert PaymentEscrow__TransferFailed();

        emit EscrowRefunded(shipmentId, escrow.manufacturer, escrow.amount);
    }
}
