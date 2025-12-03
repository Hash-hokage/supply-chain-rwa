// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MockRouter {
    event RequestSent(bytes32 indexed id);

    function sendRequest(uint64, bytes calldata, uint16, uint32, bytes32) external returns (bytes32) {
        bytes32 requestId = keccak256(abi.encodePacked(block.timestamp, msg.sender));
        emit RequestSent(requestId);
        return requestId;
    }
}
