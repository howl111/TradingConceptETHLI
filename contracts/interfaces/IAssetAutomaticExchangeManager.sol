// SPDX-License-Identifier: MIT

pragma solidity >=0.6.2 <0.8.0;

interface IAssetAutomaticExchangeManager {
    function swapExactTokenForToken(address from, address to, uint256 amount) external returns (uint256);
}