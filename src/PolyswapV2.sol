// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

import {ComposableCoW} from "@composable-cow/ComposableCoW.sol";
import {PolyswapBase} from "./PolyswapBase.sol";
import {IExchangeV3} from "./interfaces/IExchangeV3.sol";

/// @notice Protocol V2 handler shared by binary and NegRisk markets.
/// @dev BUY remaining is collateral budget, excluding fees, not remaining shares.
contract PolyswapV2 is PolyswapBase {
    IExchangeV3 public immutable polymarket;

    constructor(ComposableCoW _composableCow, IExchangeV3 _polymarket) PolyswapBase(_composableCow) {
        require(address(_polymarket) != address(0), "invalid exchange");
        polymarket = _polymarket;
    }

    function _getOrderStatus(bytes32 orderHash) internal view override returns (bool filled, uint256 remaining) {
        IExchangeV3.OrderStatus memory status = polymarket.getOrderStatus(orderHash);
        return (status.filled, uint256(status.remaining));
    }
}
