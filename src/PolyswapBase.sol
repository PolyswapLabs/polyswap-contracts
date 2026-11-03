// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

import {IConditionalOrder, GPv2Order, BaseConditionalOrder} from "@composable-cow/BaseConditionalOrder.sol";
import {ComposableCoW} from "@composable-cow/ComposableCoW.sol";
import {PolyswapOrder} from "./PolyswapOrder.sol";

string constant CONDITION_NOT_MET = "condition not met";

/// @notice Common CoW payload and collateral-consumption gate for both Polymarket protocols.
abstract contract PolyswapBase is BaseConditionalOrder {
    uint256 internal constant MIN_FILL_BPS = 1000;
    ComposableCoW public immutable composableCow;

    constructor(ComposableCoW _composableCow) {
        composableCow = _composableCow;
    }

    function _getOrderStatus(bytes32 orderHash) internal view virtual returns (bool filled, uint256 remaining);

    function getTradeableOrder(address, address, bytes32, bytes calldata staticInput, bytes calldata)
        public
        view
        override
        returns (GPv2Order.Data memory order)
    {
        PolyswapOrder.Data memory data = abi.decode(staticInput, (PolyswapOrder.Data));
        order = PolyswapOrder.orderFor(data);
        (bool filled, uint256 remaining) = _getOrderStatus(data.polymarketOrderHash);
        uint256 makerAmount = data.polymarketMakerAmount;
        uint256 consumed =
            remaining == 0 ? (filled ? makerAmount : 0) : (makerAmount > remaining ? makerAmount - remaining : 0);
        if (consumed * 10_000 < makerAmount * MIN_FILL_BPS) {
            revert IConditionalOrder.PollTryNextBlock(CONDITION_NOT_MET);
        }
    }

    function getOrderHash(PolyswapOrder.Data memory data) public view returns (bytes32) {
        return GPv2Order.hash(PolyswapOrder.orderFor(data), composableCow.domainSeparator());
    }
}
