// SPDX-License-Identifier: MIT
pragma solidity 0.6.8;

import "./access/Ownable.sol";
import "./access/AccessControl.sol";
import "./interfaces/IParamStorage.sol";
import "./interfaces/IAssetValuationManager.sol";
import "./interfaces/IAssetAutomaticExchangeManager.sol";

contract ParamKeeper is Ownable, AccessControl, IParamStorage{

  bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

  //global token address whitelist
  mapping (address => bool) public globalWhitelist;
  //address params storage
  mapping (uint16 => address) public addressParams;
  //uint params storage
  mapping (uint16 => uint256) public uintParams;
  //list of trading instruments by index 
  mapping (address => bool) public assetManagers;

  // address public priceFeeder;

  IAssetValuationManager internal valuationManager;

  IAssetAutomaticExchangeManager internal automaticExchangeManager;
  
  constructor() public {
    _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    _setupRole(MANAGER_ROLE, _msgSender());
  }

  /**
  * @dev Throws if called by any account other than the one with the Manager role granted.
  */
  modifier onlyManager() {
      require(hasRole(MANAGER_ROLE, msg.sender), "Caller is not the Manager");
      _;
  }
  function setParamAddress(uint16 _key, address _value) public onlyManager {
    addressParams[_key] = _value;
  }

  function setParamUInt256(uint16 _key, uint256 _value) public onlyManager {
    uintParams[_key] = _value;
  }

  function setAssetAutomaticExchangeManager(address _address) public onlyManager {
      automaticExchangeManager = IAssetAutomaticExchangeManager(_address);
  }

  function setAssetValuationManager(address _address) public onlyManager {
      valuationManager = IAssetValuationManager(_address);
  }

  function addAssetManager(address _manager) public onlyManager {
      assetManagers[_manager] = true;
  }

  function removeAssetManager(address _manager) public onlyManager {
      delete assetManagers[_manager];
  }

  function whitelistToken(address _token) public onlyManager {
    globalWhitelist[_token] = true;
  }

  function delistToken(address _token) public onlyManager {
    delete globalWhitelist[_token];
  }

  function getAddress(uint16 key) external override view returns (address){
    return addressParams[key];
  }

  function getUInt256(uint16 key) external override view returns (uint256){
    return uintParams[key];
  }

  function isWhitelisted(address token) public override view returns (bool) {
    return globalWhitelist[token];
  }

  function isAllowedAssetManager(address _manager) public override view returns (bool){
     return assetManagers[_manager];
  }

  function getAssetAutomaticExchangeManager() public override view returns (IAssetAutomaticExchangeManager){
    return automaticExchangeManager;
  }

  function getAssetValuationManager() public override view returns (IAssetValuationManager){
    return valuationManager;
  }

}
