// SPDX-License-Identifier: MIT

pragma solidity >=0.6.2 <0.8.0;

interface ITraderPool{
    function initiateExchangeOperation(address fromAsset, address toAsset, uint256 fromAmt, address caller, bytes calldata _calldata) external;
}