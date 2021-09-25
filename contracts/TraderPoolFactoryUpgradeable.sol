// SPDX-License-Identifier: MIT
pragma solidity 0.6.8;


import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "./upgradeable/BeaconProxy.sol";
import "./interfaces/IParamStorage.sol";
import "./interfaces/ITraderPoolInitializable.sol";
import "./interfaces/IPoolLiquidityToken.sol";

contract TraderPoolFactoryUpgradeable is AccessControlUpgradeable {

  IParamStorage public paramkeeper;

  address public positionToolManager;

  address public traderContractBeaconAddress;
  address public pltBeaconAddress;

  address public dexeAdmin;
  address public wethAddress;

  event TraderContractCreated(address newContractAddress);

   /**
    * @dev Throws if called by any account other than the one with the Admin role granted.
    */
    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Caller is not the Admin");
        _;
    }

  function initialize(address _admin, address _traderContractBeaconAddress, address _pltBeaconAddress, address _paramkeeper, address _positionToolManager, address _weth) public initializer {
    __AccessControl_init();

    _setupRole(DEFAULT_ADMIN_ROLE, _admin);
    
    dexeAdmin = _admin;
    wethAddress = _weth;
    traderContractBeaconAddress = _traderContractBeaconAddress;
    pltBeaconAddress = _pltBeaconAddress;
    paramkeeper = IParamStorage(_paramkeeper);
    positionToolManager = _positionToolManager;
  }

  function setTraderContractBeaconAddress(address _traderContractBeaconAddress) public onlyAdmin {
    traderContractBeaconAddress = _traderContractBeaconAddress;
  }

  function setDexeAdminAddress(address _dexeAdmin) public onlyAdmin {
    dexeAdmin = _dexeAdmin;
  }

  /**
  * Creates Trader Contract instance.
  * @param _traderWallet - trader's wallet that will be managing Trader Contract
  * @param _basicToken - basicToken for trader contract
  * @param _totalSupply - maxTotalSupply of Trader Contract liquidity token. 0 for unlimited supply.
  * @param _comm - commissions. Array of 3 commissions, specified in a form of natural fration each (i.e. nominator and denominator.). Format: [traderCommDenom, traderCommNom, investorCommDenom, investorCommNom, platformCommDenom, platformCommNom]
  * @param _actual - flag for setting up "actual portfolio". Set to true to enable.
  * @param _investorRestricted - flag to enable investor whitelist. Set to true to enable.
  * @param _name - Trader ERC20 token name
  * @param _symbol - Trader ERC20 token symbol
  **/
  function createTraderContract(address _traderWallet, address _basicToken, uint256 _totalSupply, uint16[6] memory _comm, bool _actual, bool _investorRestricted, string memory _name, string memory _symbol) public returns (address){
    address traderContractProxy = address(new BeaconProxy(traderContractBeaconAddress, bytes("")));
    address poolTokenProxy = address(new BeaconProxy(pltBeaconAddress, bytes("")));
    IPoolLiquidityToken(poolTokenProxy).initialize(traderContractProxy, _totalSupply, _name, _symbol);

      /**
        address[] iaddr = [
            0... _admin,
            1... _traderWallet,
            2... _basicToken,
            3... _weth,
            4... _paramkeeper,
            5... _positiontoolmanager,
            6... _dexeComm,
            7... _insurance,
            8... _pltTokenAddress,
            ]
        uint256[] iuint = [
            0... _tcNom,
            1... _tcDenom,
            ]
         */
    uint256 commissions = 0;
    //trader
    require (_comm[0] > 0, "Incorrect trader commission denom");
    commissions = commissions + _comm[0];
    commissions = commissions + (uint256(_comm[1]) << 32);
    require (_comm[2] > 0, "Incorrect investor commission denom");
    commissions = commissions + (uint256(_comm[2]) << 64);
    commissions = commissions + (uint256(_comm[3]) << 96);
    require (_comm[4] > 0, "Incorrect dexe commission denom");
    commissions = commissions + (uint256(_comm[4]) << 128);
    commissions = commissions + (uint256(_comm[5]) << 160);

    address[9] memory iaddr = [dexeAdmin, _traderWallet, _basicToken, wethAddress, address(paramkeeper),positionToolManager, getDexeCommissionAddress(), getInsuranceAddress(), poolTokenProxy];
    // uint256[4] memory iuint = [uint256(_tcNom),uint256(_tcDenom),uint256(_icNom),uint256(_icDenom)];

    ITraderPoolInitializable(traderContractProxy).initialize(iaddr, commissions, _actual, _investorRestricted);
    //
    emit TraderContractCreated(traderContractProxy);

    return traderContractProxy;
  }

  function getInsuranceAddress() public view returns (address) {
    return paramkeeper.getAddress(101);
  }

  function getDexeCommissionAddress() public view returns (address) {
    return paramkeeper.getAddress(102);
  }

}
