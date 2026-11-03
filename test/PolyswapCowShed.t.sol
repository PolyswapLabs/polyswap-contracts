// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "cowprotocol/contracts/interfaces/IERC20.sol";
import {GPv2Order} from "cowprotocol/contracts/libraries/GPv2Order.sol";
import {GPv2Transfer} from "cowprotocol/contracts/libraries/GPv2Transfer.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

import {IConditionalOrder, ComposableCoW} from "composable-cow/src/ComposableCoW.sol";
import {IValueFactory} from "composable-cow/src/interfaces/IValueFactory.sol";

import {Trading} from "exchange/mixins/Trading.sol";

import {PolyswapOrder} from "../src/PolyswapOrder.sol";
import {Polyswap, CONDITION_NOT_MET} from "../src/Polyswap.sol";
import {MockPolymarket} from "./MockPolymarket.sol";
import {ShedCall, ICOWShedFactory, ICOWShed, IComposableCowPoller} from "./interfaces/ICowShed.sol";

contract TestToken is ERC20 {
    constructor(string memory symbol) ERC20(symbol, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

interface IVaultRelayer {
    function transferFromAccounts(GPv2Transfer.Data[] calldata transfers) external;
}

/**
 * @title PolyswapCowShedTest
 * @dev End-to-end compatibility of Polyswap orders owned by an EOA's CoW Shed
 *      (COWShedForComposableCoW) and funded just-in-time by the ComposableCowPoller,
 *      mirroring CoW Swap's TWAP-for-EOA flow against the live Polygon deployments.
 */
contract PolyswapCowShedTest is Test {
    uint256 internal constant FORK_BLOCK = 95_600_000;

    ComposableCoW internal constant COMPOSABLE_COW = ComposableCoW(0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74);
    ICOWShedFactory internal constant SHED_FACTORY = ICOWShedFactory(0x221c28Ec177CF7da6f837DfD0052Ba8F265Fb4CA);
    IComposableCowPoller internal constant POLLER = IComposableCowPoller(0xd8088f0d57dB91AC6404FB3a9723A890100a6bB3);
    IValueFactory internal constant VALUE_FACTORY = IValueFactory(0x52eD56Da04309Aca4c3FECC595298d80C2f16BAc);
    address internal constant SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address internal constant VAULT_RELAYER = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;

    /// @dev Same gas budget CoW Swap declares for the `pollFunds` pre-hook.
    uint256 internal constant POLL_FUNDS_HOOK_GAS_LIMIT = 350_000;
    bytes4 internal constant ERC1271_MAGIC = 0x1626ba7e;
    bytes32 internal constant POLYMARKET_ORDER_HASH = keccak256("polymarket-order");
    uint256 internal constant MAKER_AMOUNT = 1_000_000;
    uint256 internal constant SELL_AMOUNT = 100e6;

    MockPolymarket internal polymarket;
    Polyswap internal polyswap;
    TestToken internal sellToken;
    TestToken internal buyToken;

    address internal eoa;
    address internal shed;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("polygon"), FORK_BLOCK);

        polymarket = new MockPolymarket();
        polyswap = new Polyswap(COMPOSABLE_COW, Trading(address(polymarket)));
        sellToken = new TestToken("SELL");
        buyToken = new TestToken("BUY");

        eoa = makeAddr("eoa");
        shed = SHED_FACTORY.proxyOf(eoa);
        sellToken.mint(eoa, SELL_AMOUNT * 10);

        vm.prank(eoa);
        sellToken.approve(address(POLLER), type(uint256).max);
    }

    // ===== Tests =====

    function test_scheduleId_goldenVector() public view {
        IComposableCowPoller.Schedule memory schedule = IComposableCowPoller.Schedule({
            handler: 0x2222222222222222222222222222222222222222,
            authEpoch: 0,
            funder: 0x1111111111111111111111111111111111111111,
            owner: 0x3333333333333333333333333333333333333333,
            salt: 0x4444444444444444444444444444444444444444444444444444444444444444,
            staticInput: hex"deadbeef"
        });
        // Shared with the dapp unit tests (src/lib/cowShed.test.ts).
        assertEq(POLLER.scheduleId(schedule), 0x719f245426fdedc5147639c5656c03495e74ad3a23c5259396e667ba90b7ab4b);
    }

    function test_poller_pinnedToShedFactory() public view {
        assertEq(POLLER.COW_SHED_FACTORY(), address(SHED_FACTORY));
    }

    function test_setup_executeOwnHooks_deploysShedAndCreatesOrder() public {
        (IConditionalOrder.ConditionalOrderParams memory params, IComposableCowPoller.Schedule memory schedule) =
            _order(keccak256("salt-1"));
        assertEq(shed.code.length, 0);

        vm.expectEmit(true, false, false, true, address(COMPOSABLE_COW));
        emit ComposableCoW.ConditionalOrderCreated(shed, params);
        vm.prank(eoa);
        address proxy = SHED_FACTORY.executeOwnHooks(_setupCalls(params, schedule, true));

        assertEq(proxy, shed);
        assertGt(shed.code.length, 0);
        assertTrue(COMPOSABLE_COW.singleOrders(shed, COMPOSABLE_COW.hash(params)));
        assertEq(sellToken.allowance(shed, VAULT_RELAYER), type(uint256).max);
        assertEq(sellToken.balanceOf(shed), 0, "funds stay on the EOA until settlement");
    }

    function test_tradeableOrder_validShedSignature() public {
        (IConditionalOrder.ConditionalOrderParams memory params,) = _setupOrder(keccak256("salt-1"));

        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.PollTryNextBlock.selector, CONDITION_NOT_MET));
        COMPOSABLE_COW.getTradeableOrderWithSignature(shed, params, "", new bytes32[](0));

        _openGate();
        (GPv2Order.Data memory order, bytes memory signature) =
            COMPOSABLE_COW.getTradeableOrderWithSignature(shed, params, "", new bytes32[](0));
        assertEq(order.receiver, eoa);
        assertEq(order.sellAmount, SELL_AMOUNT);

        vm.prank(SETTLEMENT);
        assertEq(ICOWShed(shed).isValidSignature(_digest(order), signature), ERC1271_MAGIC);
    }

    function test_pollFunds_pullsSellAmountOnce() public {
        (IConditionalOrder.ConditionalOrderParams memory params, bytes32 id) = _setupOrder(keccak256("salt-1"));
        uint256 eoaBalance = sellToken.balanceOf(eoa);

        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.PollTryNextBlock.selector, CONDITION_NOT_MET));
        POLLER.pollFunds(id);

        _openGate();
        uint256 gasBefore = gasleft();
        assertTrue(POLLER.pollFunds(id));
        assertLt(gasBefore - gasleft(), POLL_FUNDS_HOOK_GAS_LIMIT);

        assertEq(sellToken.balanceOf(eoa), eoaBalance - SELL_AMOUNT);
        assertEq(sellToken.balanceOf(shed), SELL_AMOUNT);
        assertTrue(POLLER.funded(id, _digest(_tradeableOrder(params))));

        assertFalse(POLLER.pollFunds(id), "second poll is a no-op");
        assertEq(sellToken.balanceOf(shed), SELL_AMOUNT);
    }

    function test_vaultRelayer_pullsFromShed() public {
        (, bytes32 id) = _setupOrder(keccak256("salt-1"));
        _openGate();
        POLLER.pollFunds(id);

        GPv2Transfer.Data[] memory transfers = new GPv2Transfer.Data[](1);
        transfers[0] = GPv2Transfer.Data({
            account: shed, token: IERC20(address(sellToken)), amount: SELL_AMOUNT, balance: GPv2Order.BALANCE_ERC20
        });
        vm.prank(SETTLEMENT);
        IVaultRelayer(VAULT_RELAYER).transferFromAccounts(transfers);

        assertEq(sellToken.balanceOf(SETTLEMENT), SELL_AMOUNT);
        assertEq(sellToken.balanceOf(shed), 0);
    }

    function test_cancel_removesOrderAndSweepsFunds() public {
        (IConditionalOrder.ConditionalOrderParams memory params, bytes32 id) = _setupOrder(keccak256("salt-1"));
        uint256 eoaBalance = sellToken.balanceOf(eoa);
        _openGate();
        (GPv2Order.Data memory order, bytes memory signature) =
            COMPOSABLE_COW.getTradeableOrderWithSignature(shed, params, "", new bytes32[](0));
        POLLER.pollFunds(id); // permissionless: funds can land in the shed before settlement

        ShedCall[] memory calls = new ShedCall[](2);
        calls[0] = _call(address(COMPOSABLE_COW), abi.encodeCall(ComposableCoW.remove, (COMPOSABLE_COW.hash(params))));
        calls[1] = _call(address(sellToken), abi.encodeCall(ERC20.transfer, (eoa, SELL_AMOUNT)));
        vm.prank(eoa);
        ICOWShed(shed).trustedExecuteHooks(calls);

        assertFalse(COMPOSABLE_COW.singleOrders(shed, COMPOSABLE_COW.hash(params)));
        assertEq(sellToken.balanceOf(eoa), eoaBalance);
        assertEq(sellToken.balanceOf(shed), 0);

        vm.expectRevert(IComposableCowPoller.OrderNotLive.selector);
        POLLER.pollFunds(id);

        bytes32 digest = _digest(order);
        vm.prank(SETTLEMENT);
        vm.expectRevert(ComposableCoW.SingleOrderNotAuthed.selector);
        ICOWShed(shed).isValidSignature(digest, signature);
    }

    function test_secondOrder_onDeployedShed() public {
        _setupOrder(keccak256("salt-1"));
        (IConditionalOrder.ConditionalOrderParams memory params, IComposableCowPoller.Schedule memory schedule) =
            _order(keccak256("salt-2"));

        vm.prank(eoa);
        ICOWShed(shed).trustedExecuteHooks(_setupCalls(params, schedule, false));

        assertTrue(COMPOSABLE_COW.singleOrders(shed, COMPOSABLE_COW.hash(params)));
        _openGate();
        assertTrue(POLLER.pollFunds(POLLER.scheduleId(schedule)));
        assertEq(sellToken.balanceOf(shed), SELL_AMOUNT);
    }

    function test_revert_strangerCannotExecuteOnShed() public {
        _setupOrder(keccak256("salt-1"));
        vm.prank(makeAddr("stranger"));
        vm.expectRevert(ICOWShed.OnlyTrustedRole.selector);
        ICOWShed(shed).trustedExecuteHooks(new ShedCall[](0));
    }

    function test_revert_cannotRegisterScheduleFundedByAnotherAccount() public {
        (, IComposableCowPoller.Schedule memory schedule) = _order(keccak256("salt-1"));

        vm.prank(makeAddr("stranger"));
        vm.expectRevert(IComposableCowPoller.UnauthorizedShed.selector);
        POLLER.registerFromShed(schedule);

        // Even from the attacker's own shed, the funder must be that shed's owner.
        address attacker = makeAddr("attacker");
        schedule.owner = SHED_FACTORY.proxyOf(attacker);
        ShedCall[] memory calls = new ShedCall[](1);
        calls[0] = _call(address(POLLER), abi.encodeCall(IComposableCowPoller.registerFromShed, (schedule)));
        vm.prank(attacker);
        vm.expectRevert(IComposableCowPoller.UnauthorizedShed.selector);
        SHED_FACTORY.executeOwnHooks(calls);
    }

    // ===== Helpers =====

    function _order(bytes32 salt)
        internal
        view
        returns (IConditionalOrder.ConditionalOrderParams memory params, IComposableCowPoller.Schedule memory schedule)
    {
        bytes memory staticInput = abi.encode(
            PolyswapOrder.Data({
                sellToken: IERC20(address(sellToken)),
                buyToken: IERC20(address(buyToken)),
                receiver: eoa,
                sellAmount: SELL_AMOUNT,
                minBuyAmount: 1,
                t0: block.timestamp,
                t: block.timestamp + 1 days,
                polymarketOrderHash: POLYMARKET_ORDER_HASH,
                appData: keccak256("app-data-with-pollFunds-hook"),
                polymarketMakerAmount: MAKER_AMOUNT
            })
        );
        params = IConditionalOrder.ConditionalOrderParams({handler: polyswap, salt: salt, staticInput: staticInput});
        schedule = IComposableCowPoller.Schedule({
            handler: address(polyswap), authEpoch: 0, funder: eoa, owner: shed, salt: salt, staticInput: staticInput
        });
    }

    /// @dev Same call ordering as CoW Swap's `getEoaTwapOrderShedCalls`.
    function _setupCalls(
        IConditionalOrder.ConditionalOrderParams memory params,
        IComposableCowPoller.Schedule memory schedule,
        bool withApproval
    ) internal view returns (ShedCall[] memory calls) {
        calls = new ShedCall[](withApproval ? 3 : 2);
        uint256 i;
        calls[i++] = _call(address(POLLER), abi.encodeCall(IComposableCowPoller.registerFromShed, (schedule)));
        if (withApproval) {
            calls[i++] = _call(address(sellToken), abi.encodeCall(ERC20.approve, (VAULT_RELAYER, type(uint256).max)));
        }
        calls[i] = _call(
            address(COMPOSABLE_COW), abi.encodeCall(ComposableCoW.createWithContext, (params, VALUE_FACTORY, "", true))
        );
    }

    function _setupOrder(bytes32 salt)
        internal
        returns (IConditionalOrder.ConditionalOrderParams memory params, bytes32 id)
    {
        IComposableCowPoller.Schedule memory schedule;
        (params, schedule) = _order(salt);
        vm.prank(eoa);
        SHED_FACTORY.executeOwnHooks(_setupCalls(params, schedule, true));
        id = POLLER.scheduleId(schedule);
    }

    function _openGate() internal {
        polymarket.setOrderStatus(POLYMARKET_ORDER_HASH, true, 0);
    }

    function _tradeableOrder(IConditionalOrder.ConditionalOrderParams memory params)
        internal
        view
        returns (GPv2Order.Data memory order)
    {
        (order,) = COMPOSABLE_COW.getTradeableOrderWithSignature(shed, params, "", new bytes32[](0));
    }

    function _digest(GPv2Order.Data memory order) internal view returns (bytes32) {
        return GPv2Order.hash(order, COMPOSABLE_COW.domainSeparator());
    }

    function _call(address target, bytes memory callData) internal pure returns (ShedCall memory) {
        return ShedCall({target: target, value: 0, callData: callData, allowFailure: false, isDelegateCall: false});
    }
}
