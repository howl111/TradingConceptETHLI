// SPDX-License-Identifier: MIT

pragma solidity >=0.6.2 <0.8.0;

interface IAssetExchangeManager {
    function execute(bytes calldata _calldata) external returns (bool);
}