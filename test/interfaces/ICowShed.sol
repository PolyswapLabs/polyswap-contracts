// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

/// @dev Minimal interfaces for the deployed CoW Shed (v2.1.0, ComposableCoW flavour) and
///      ComposableCowPoller (v1.2.0). See https://github.com/cowdao-grants/cow-shed and
///      https://github.com/cowprotocol/composable-cow/blob/main/src/ComposableCowPoller.sol

struct ShedCall {
    address target;
    uint256 value;
    bytes callData;
    bool allowFailure;
    bool isDelegateCall;
}

interface ICOWShedFactory {
    function proxyOf(address who) external view returns (address);
    function executeOwnHooks(ShedCall[] calldata calls) external payable returns (address proxy);
}

interface ICOWShed {
    error OnlyTrustedRole();

    function trustedExecuteHooks(ShedCall[] calldata calls) external;
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4);
}

interface IComposableCowPoller {
    struct Schedule {
        address handler;
        uint96 authEpoch;
        address funder;
        address owner;
        bytes32 salt;
        bytes staticInput;
    }

    error UnauthorizedShed();
    error OrderNotLive();

    function COW_SHED_FACTORY() external view returns (address);
    function scheduleId(Schedule calldata schedule) external pure returns (bytes32);
    function registerFromShed(Schedule calldata schedule) external returns (bytes32 id);
    function pollFunds(bytes32 id) external returns (bool);
    function funded(bytes32 id, bytes32 orderDigest) external view returns (bool);
}
