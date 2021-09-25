// SPDX-License-Identifier: MIT

pragma solidity >=0.6.2 <0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface IPoolLiquidityToken is IERC20Upgradeable{
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amountLiquidity) external;
    // function decimals() external view returns (uint8);
    function initialize(address _owner, uint256 _maxPoolTotalSupply, string calldata name_, string calldata symbol_) external;
}