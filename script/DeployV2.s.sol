// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ComposableCoW} from "@composable-cow/ComposableCoW.sol";
import {PolyswapV2} from "../src/PolyswapV2.sol";
import {IExchangeV3} from "../src/interfaces/IExchangeV3.sol";

/// @notice Deploy only the additional V2 handler; retain both legacy deployments.
/// @dev Prepared for a later explicit deployment. Never run automatically by tests or CI.
contract DeployV2 is Script {
    function run() external {
        require(block.chainid == 137, "expected Polygon");
        address exchange =
            vm.envOr("POLYMARKET_EXCHANGE_V3_ADDRESS", address(0xe3333700cA9d93003F00f0F71f8515005F6c00Aa));
        require(exchange.code.length > 0, "exchange has no code");
        ComposableCoW cow = ComposableCoW(vm.envAddress("COMPOSABLE_COW"));
        require(address(cow).code.length > 0, "ComposableCoW has no code");
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        PolyswapV2 handler = new PolyswapV2(cow, IExchangeV3(exchange));
        vm.stopBroadcast();
        console.log("NEXT_PUBLIC_POLYSWAP_HANDLER_V2=", address(handler));
    }
}
