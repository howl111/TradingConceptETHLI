// SPDX-License-Identifier: MIT

pragma solidity >=0.6.2 <0.8.0;

import "./IAssetValuationManager.sol";
import "./IAssetAutomaticExchangeManager.sol";

interface IParamStorage{
    function getAddress(uint16 key) external view returns (address);
    function getUInt256(uint16 key) external view returns (uint256);
    function isWhitelisted(address token) external view returns (bool);
    function isAllowedAssetManager(address _manager) external view returns (bool);
    function getAssetAutomaticExchangeManager() external view returns (IAssetAutomaticExchangeManager);
    function getAssetValuationManager() external view returns (IAssetValuationManager);
}