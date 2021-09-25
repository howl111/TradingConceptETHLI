// SPDX-License-Identifier: MIT

pragma solidity >=0.6.2 <0.8.0;

interface ITraderPoolInitializable{
  function initialize(address[9] calldata iaddr, uint256 commissions, bool _actual, bool _investorRestricted) external;
}