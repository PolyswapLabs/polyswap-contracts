// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

import {Test} from "forge-std/Test.sol";
import {ComposableCoW} from "@composable-cow/ComposableCoW.sol";
import {IConditionalOrder} from "@composable-cow/interfaces/IConditionalOrder.sol";
import {IERC20} from "cowprotocol/contracts/interfaces/IERC20.sol";
import {PolyswapOrder} from "../src/PolyswapOrder.sol";
import {PolyswapV2} from "../src/PolyswapV2.sol";
import {IExchangeV3} from "../src/interfaces/IExchangeV3.sol";

contract MockExchangeV3 is IExchangeV3 {
    mapping(bytes32 => OrderStatus) public statuses;

    function setStatus(bytes32 hash, bool filled, uint248 remaining) external {
        statuses[hash] = OrderStatus(filled, remaining);
    }

    function getOrderStatus(bytes32 hash) external view returns (OrderStatus memory) {
        return statuses[hash];
    }
}

contract PolyswapV2GateTest is Test {
    MockExchangeV3 exchange;
    PolyswapV2 handler;
    bytes32 constant HASH = bytes32(uint256(123));

    function setUp() public {
        exchange = new MockExchangeV3();
        handler = new PolyswapV2(ComposableCoW(address(0)), exchange);
    }

    function payload(uint256 maker) internal view returns (bytes memory) {
        return abi.encode(
            PolyswapOrder.Data({
                sellToken: IERC20(address(1)),
                buyToken: IERC20(address(2)),
                receiver: address(3),
                sellAmount: 100,
                minBuyAmount: 90,
                t0: block.timestamp,
                t: block.timestamp + 1 days,
                polymarketOrderHash: HASH,
                appData: bytes32(0),
                polymarketMakerAmount: maker
            })
        );
    }

    function testUntouchedDoesNotArm() public {
        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.PollTryNextBlock.selector, "condition not met"));
        handler.getTradeableOrder(address(0), address(0), bytes32(0), payload(1_000_000), "");
    }

    function testFillBoundaries() public {
        exchange.setStatus(HASH, false, 900_001);
        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.PollTryNextBlock.selector, "condition not met"));
        handler.getTradeableOrder(address(0), address(0), bytes32(0), payload(1_000_000), "");
        exchange.setStatus(HASH, false, 900_000);
        assertEq(handler.getTradeableOrder(address(0), address(0), bytes32(0), payload(1_000_000), "").sellAmount, 100);
        exchange.setStatus(HASH, true, 0);
        assertEq(handler.getTradeableOrder(address(0), address(0), bytes32(0), payload(1_000_000), "").sellAmount, 100);
    }

    function testPriceImprovementDustArms() public {
        exchange.setStatus(HASH, false, 12_500);
        assertEq(handler.getTradeableOrder(address(0), address(0), bytes32(0), payload(1_000_000), "").buyAmount, 90);
    }

    function testFuzzCollateralGate(uint128 maker, uint248 remaining, bool filled) public {
        maker = uint128(bound(maker, 1, type(uint128).max));
        exchange.setStatus(HASH, filled, remaining);
        uint256 consumed = remaining == 0 ? (filled ? maker : 0) : maker > remaining ? maker - remaining : 0;
        if (consumed * 10_000 < uint256(maker) * 1000) {
            vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.PollTryNextBlock.selector, "condition not met"));
        }
        handler.getTradeableOrder(address(0), address(0), bytes32(0), payload(maker), "");
    }
}
