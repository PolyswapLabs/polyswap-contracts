// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

import {ComposableCoW} from "@composable-cow/ComposableCoW.sol";
import {Trading} from "exchange/mixins/Trading.sol";
import {OrderStatus} from "exchange/libraries/OrderStructs.sol";
import {PolyswapBase, CONDITION_NOT_MET} from "./PolyswapBase.sol";

/// @notice Legacy CTF handler. Existing constructor and payload ABI are retained.
contract Polyswap is PolyswapBase {
    Trading public immutable polymarket;

    constructor(ComposableCoW _composableCow, Trading _polymarket) PolyswapBase(_composableCow) {
        polymarket = _polymarket;
    }

    function _getOrderStatus(bytes32 orderHash) internal view override returns (bool filled, uint256 remaining) {
        OrderStatus memory status = polymarket.getOrderStatus(orderHash);
        return (status.isFilledOrCancelled, status.remaining);
    }
}
