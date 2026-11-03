// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

/// @notice ExchangeV3 uses the same selector as CTF exchanges, with distinct fill semantics.
interface IExchangeV3 {
    struct OrderStatus {
        bool filled;
        uint248 remaining;
    }
    function getOrderStatus(bytes32 orderHash) external view returns (OrderStatus memory);
}
