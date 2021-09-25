// SPDX-License-Identifier: MIT

pragma solidity >=0.6.2 <0.8.0;

interface IPool{
    
    
    function getLatestPrice() external view returns (uint256);
    function getPriceDecimals() external view returns (uint256);
    function getBasicToken() external view returns (address);
    function getBasicTokenDecimals() external view returns (uint256);
}