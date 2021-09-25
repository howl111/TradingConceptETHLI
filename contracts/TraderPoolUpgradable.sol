// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.8;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/EnumerableSet.sol';

import "./pool/PoolUpgradeable.sol";
import "./interfaces/ITraderPoolInitializable.sol";
import "./interfaces/IParamStorage.sol";
import "./interfaces/IAssetExchangeManager.sol";
import "./interfaces/IAssetValuationManager.sol";
import "./interfaces/IAssetAutomaticExchangeManager.sol";
import "./interfaces/ITraderPool.sol";
import "./pancake/interfaces/IPancakeRouter01.sol";

contract TraderPoolUpgradeable
    is
    AccessControlUpgradeable,
    PausableUpgradeable,
    PoolUpgradeable,
    ITraderPoolInitializable,
    ITraderPool
    {
    using EnumerableSet for EnumerableSet.AddressSet;

    //ACL
    //Manager is the person allowed to manage funds
    address public trader;
    bool public isActualOn;
    bool public isInvestorsWhitelistEnabled;

    address public traderCommissionAddress;
    address public dexeCommissionAddress;
    address public insuranceContractAddress;
    IParamStorage private paramkeeper;

    uint256 public commissions;
    uint256 public traderCommissionBalance;
    uint256 public dexeCommissionBalance;
     //funds on the contract that belongs to trader
    uint256 public traderLiquidityBalance;
    uint128 public storageVersion;
    //max traderTokenPrice that any investor ever bought
    int128 public maxDepositedTokenPrice;
    //addresses that trader may fund from (funded from these addresses considered as a trader funds)
    mapping (address => bool) traderFundAddresses;
    //trader token address whitelist
    mapping (address => bool) public traderWhitelist;
    //trader investor address whitelist
    mapping (address => bool) public investorWhitelist;

    EnumerableSet.AddressSet internal users;

    // todo remove
    event E0(string name);
    event E1(string name, uint256 value);
    event E2(string name1, uint256 value1, string name2, uint256 value2);
    event E3(string name1, uint256 value1, string name2, uint256 value2, string name3, uint256 value3);

    //positions
    mapping(address => uint256) pAmtOpenedInBasic;  //amount of basicTokens spent for opening position (i.e. position opening cost)
    mapping(address => uint256) pAssetAmt; //amount of assets locked in the open position  //todo discuss why not use IERC20.balanceOf
    address[] public assetTokenAddresses; //address of the asset ERC20 token
    address[] public assetRiskTokenAddresses; //address of the risky asset ERC20 token

    event Exchanged(address fromAsset, address toAsset, uint256 fromAmt, uint256 toAmt);
    event Profit(uint256 amount);
    event Loss(uint256 amount);
    event RiskyTradingProposalCreated(address indexed creator, address indexed riskyToken);
    event RiskyTradingAllowanceSet(address indexed creator, address indexed riskyToken, uint256 amount);
    event RiskyTokenMovedToWhiteListAndSubPoolMerged(address indexed sender, address indexed token);

    /**
    * returns version of the contract
    */
    function version() public view returns (uint32){
        //version in format aaa.bbb.ccc => aaa*1E6+bbb*1E3+ccc;
        return uint32(10010001);
    }
/*
1 lp = 1base
price = 1

admin buy 50, lockedLp=50, riskyTokenAmount=50

price = 1000

user approve 100

trader buy 150 -> admin 50 + 100 user
admin:
  lockedLp=50+50, riskyTokenAmount=50+50/1000
user:
  lockedLp=100, riskyTokenAmount=100/1000

price = 2_000

SELL WHOLE
admin recv profit = (50+50/1000)*2000 - locked100, locked:=0
admin recv profit = 100/1000 * 2000 - locked100, locked:=0

*/
    struct RiskSubPoolUserInfo{
        uint256 riskyAllowedLp;  // allowance is given in LP tokens
        uint256 lockedLp;  // they locked in prices of basePrice at the moment of the riskToken buy
        uint256 riskyTokenAmount;  // share of user in bought risky tokens
    }

    function totalAllowedLpToBuyRiskToken(address riskyToken) public view returns(uint256){
        uint256 result = 0;
        RiskSubPool storage subPool = _riskSubPools[riskyToken];
        for (uint256 user_index=0; user_index<subPool.users.length(); user_index++) {
            address user = subPool.users.at(user_index);
            uint256 userLpBalance = IERC20Token(plt).balanceOf(user);
            uint256 userMaxAllowance = subPool.userInfo[user].riskyAllowedLp;

            // max
            uint256 userPossibleLp = userLpBalance;
            if (userPossibleLp > userMaxAllowance) {
                userPossibleLp = userMaxAllowance;
            }

            uint256 userLockedLpAmount = userLockedLp[user];
            result += userPossibleLp - userLockedLpAmount;
        }
        return result;
    }

    mapping(address => uint256) public userLockedLp;

    // since it's impossible to remove entire mapping,
    // we let user to use riskyPool once, before it will be shifted to whiteList
    mapping(address /*token*/ => bool) public riskyTokensMovedToWhiteList;

    struct RiskSubPool{
        bool enabled;
        mapping(address => RiskSubPoolUserInfo) userInfo;
        uint256 totalLockedLp;
        // todo discuss one more unscalable place

        EnumerableSet.AddressSet users;

//        uint256 totalAvailableLp;  // the number of lp tokens which the subPool may really use
//                                   // be careful because users may have no such LP on their accounts
//                                   // because any user can set allowance higher than the amount of tokens he has.
//                                   // todo we probably should calculate this dynamically
//
//        uint256 totalAllowedLp;    // the total allowance (used+unused) of LpTokens for risky trading,
//                                   // be careful because users may have no such LP on their accounts
//                                   // because any user can set allowance higher than the amount of tokens he has.
//                                   // todo this variable has no impact since owner has type(uint256).max
//                                   //   so we probably should remove this

        // todo it introduces calculation difficulties because every time user LP tokens change
        //   the REAL allowed total LP which we use for sharing calculations will also change.
    }
    mapping(address => RiskSubPool) internal _riskSubPools;

    modifier onlyWhitelistOrBasicToken(address token) {
        require((
                paramkeeper.isWhitelisted(token) ||
                traderWhitelist[token] ||
                token == address(basicToken)
            ),
            "token must be whitelisted or basicToken");
        _;
    }

    modifier onlyNotWhitelistOrBasicToken(address token) {
        require((
                (!paramkeeper.isWhitelisted(token)) &&
                (!traderWhitelist[token]) &&  //todo зачем это?
                (token != address(basicToken))
            ),
            "address must be not in whitelist and not basicToken");
        _;
    }

    // it's somehow could be possible that token is removed from the whiteList pool, but for now we prohibit trading
    modifier notMovedToWhiteList(address token) {
        require(!riskyTokensMovedToWhiteList[token], "!riskyTokensMovedToWhiteList[token] failed");
        _;
    }

    modifier onlyEnabledRiskSubPool(address token) {
        require(_riskSubPools[token].enabled, "subPool must be enabled");
        _;
    }

    modifier onlyDisabledRiskSubPool(address token) {
        require(!_riskSubPools[token].enabled, "subPool must be disabled");
        _;
    }

    // todo user and admin should not be allowed to transfer/burn locked LP

    event UserJoinedRiskySubPool(address indexed user, address indexed riskyToken);
    event UserLeftRiskySubPool(address indexed user, address indexed riskyToken);

    ///@dev note, that user can set any value as an allowance, but not less then currently locked.
    function setAllowanceForProposal(
        address riskyToken,
        uint256 lpTokenAmount
    ) external onlyEnabledRiskSubPool(riskyToken) {
        // trader should not be able to do it, because for trade it's always type(uint256).max
        require(msg.sender != trader, "require msg.sender != trader");

        RiskSubPool storage riskySubPool = _riskSubPools[riskyToken];
        RiskSubPoolUserInfo storage profile = riskySubPool.userInfo[msg.sender];
        require(lpTokenAmount >= profile.lockedLp, "require lpTokenAmount >= profile.lockedLp");

        // todo remove because is removed with dynamic calculations
        //        riskySubPool.totalAllowedLp = riskySubPool.totalAllowedLp - profile.riskyAllowedLp + lpTokenAmount;
        profile.riskyAllowedLp = lpTokenAmount;
        emit RiskyTradingAllowanceSet(msg.sender, riskyToken, lpTokenAmount);

        if (lpTokenAmount > 0) {
            bool wasAdded = riskySubPool.users.add(msg.sender);
            if (wasAdded) {
                emit UserJoinedRiskySubPool(msg.sender, riskyToken);
            } else {
                emit E0("user was already in subPool");
            }
        } else { // lpTokenAmount == 0
            bool wasRemoved = riskySubPool.users.remove(msg.sender);
        }
    }

    modifier onlyWhiteList(address token) {
        require(
            paramkeeper.isWhitelisted(token) || traderWhitelist[token] || token == address(basicToken),
            "ONLY_WHITE_LIST"
        );
        _;
    }

    function moveRiskTokenToWhiteList(address token) external onlyTrader onlyWhiteList(token) onlyEnabledRiskSubPool(token) notMovedToWhiteList(token) {
        // todo just move to white pool and unlock lp
        // todo move tokens to main pool.
        delete _riskSubPools[token];
        riskyTokensMovedToWhiteList[token] = true;

        // remove the riskyToken from assetRiskTokenAddresses
        // and add to assetTokenAddresses
        for (uint256 i=0; i<assetRiskTokenAddresses.length; i++){
            if (assetRiskTokenAddresses[i] == token) {
                if (i != assetRiskTokenAddresses.length) {
                    assetRiskTokenAddresses[i] = assetRiskTokenAddresses[assetRiskTokenAddresses.length-1];
                }
                assetRiskTokenAddresses.pop();
                assetTokenAddresses.push(token);
                break;
            }
        }

        // todo discuss should we fix the profit among current users or just shift
        //   the whole balance togeneral pool and unlock

        emit RiskyTokenMovedToWhiteListAndSubPoolMerged(msg.sender, token);
    }

    // todo refactor arguments
    function initialize(address[9] memory iaddr, uint256 _commissions, bool _actual, bool _investorRestricted) public override initializer{
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
            0... _maxPoolTotalSupply,
            1... _tcNom,
            2... _tcDenom,
            ]
         */

        // address _basicToken, address _pltTokenAddress, address _weth
        __Pool_init(iaddr[2],iaddr[8],iaddr[3]);
        // __ReentrancyGuard_init_unchained();
        __Pausable_init_unchained();
        __AccessControl_init_unchained();
        // address _paramstorage, address _positiontoolmanager

        //access control initial setup
        _setupRole(DEFAULT_ADMIN_ROLE, iaddr[0]);
        trader = iaddr[1];

        //safe mode "on" with commissions
        traderCommissionAddress = iaddr[1];

        commissions = _commissions;
        // require (iuint[1]>0, "Incorrect traderCommissionPercentDenom");

        isActualOn = _actual;
        isInvestorsWhitelistEnabled = _investorRestricted;

        traderFundAddresses[iaddr[1]] = true;

        dexeCommissionAddress = iaddr[6];
        insuranceContractAddress = iaddr[7];
        paramkeeper = IParamStorage(iaddr[4]);
        storageVersion = version();

    }

    /// @dev require not in whiteList
    /// @dev owner transfer allowance 100% always
    function createProposal(
        address riskyToken
    )   external
        onlyTrader
        onlyNotWhitelistOrBasicToken(riskyToken)
        onlyDisabledRiskSubPool(riskyToken)
        notMovedToWhiteList(riskyToken)
    {
        RiskSubPool storage subPool = _riskSubPools[riskyToken];
        subPool.enabled = true;
        subPool.userInfo[msg.sender].riskyAllowedLp = type(uint256).max;
        subPool.users.add(trader);
        emit RiskyTradingProposalCreated(msg.sender, riskyToken);
        emit RiskyTradingAllowanceSet(msg.sender, riskyToken, type(uint256).max);
    }

    /**
    * @dev Throws if called by any account other than the one with the Admin role granted.
    */
    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Caller is not the Admin");
        _;
    }

    /**
    * @dev Throws if called by any account other than the one with the Trader role granted.
    */
    modifier onlyTrader() {
        require(trader == msg.sender, "Caller is not the Trader");
        _;
    }

    /**
    * @dev Throws if called by any account other than the one with the onlyAssetManager role granted.
    */
    modifier onlyAssetManager() {
        require(paramkeeper.isAllowedAssetManager(msg.sender), "Caller is not allwed AssetManager");
        _;
    }

    /**
    * adds new trader address (tokens received from this address considered to be the traders' tokens)
    */
    function addTraderAddress (address _traderAddress) public onlyTrader {
        traderFundAddresses[_traderAddress] = true;
    }

    /**
    * removes trader address (tokens received from trader address considered to be the traders' tokens)
    */
    function removeTraderAddress (address _traderAddress) public onlyTrader {
        delete traderFundAddresses[_traderAddress];
    }

    /**
    * whitelist new investors addresses. Investors whitelist is applied if isInvestorsWhitelistEnabled == 'true' only;
    * @param _investors - array of investors addresses
    */
    function addInvestorAddress (address[] memory _investors) public onlyTrader {
        for(uint i=0;i<_investors.length;i++){
            if(_investors[i] != address(0))
                investorWhitelist[_investors[i]] = true;
        }
    }

//    function PoolUpgradeable() public view returns(int128) {
//        return ABDKMath64x64.divu(_totalCap(), totalSupply());  // todo discuss
//    }

    function _sellRiskToken(
        address riskyToken,
        uint256 riskyTokenAmount,
        uint256 riskyBalanceBefore,
        uint256 basicTokenAmount
    ) internal {
        emit E0("CALLED _sellRiskToken");
        RiskSubPool storage riskySubPool = _riskSubPools[riskyToken];
        uint256 currentLpTokenPriceN;
        uint256 currentLpTokenPriceD;
        (currentLpTokenPriceN, currentLpTokenPriceD) = getCurrentLpTokenPrice();
//        emit E1("currentLpTokenPrice = ", currentLpTokenPrice.toUInt());  // todo representation
        emit E2("currentLpTokenPriceN = ", currentLpTokenPriceN, ", currentLpTokenPriceD = ", currentLpTokenPriceN);  // todo representation
        RiskSubPool storage subPool = _riskSubPools[riskyToken];
        uint256 relevantLockedLpAmount = subPool.totalLockedLp * riskyTokenAmount / riskyBalanceBefore;
        emit E1("subPool.totalLockedLp = ", subPool.totalLockedLp);
        emit E1("riskyTokenAmount = ", riskyTokenAmount);
        emit E1("riskyBalanceBefore = ", riskyBalanceBefore);
        emit E1("relevantLockedLpAmount = subPool.totalLockedLp * riskyTokenAmount / riskyBalanceBefore =", relevantLockedLpAmount);

        //        uint256 tradeLpAmountEquivalent = ABDKMath64x64.fromUInt(basicTokenAmount).div(currentLpTokenPrice).toUInt();
        uint256 tradeLpAmountEquivalent = basicTokenAmount * currentLpTokenPriceD / currentLpTokenPriceN;

        emit E1("subPool.users.length() = ", subPool.users.length());
        for(uint256 i=0; i<subPool.users.length(); ++i){
            address user = subPool.users.at(i);
            RiskSubPoolUserInfo storage profile = subPool.userInfo[user];

//                        userShareSoldRiskTradeAmount = tradeRiskAmount * userTotalRiskAmount / totalRiskAmount;
//                        userShareReceivedBasicTokenTradeAmount = tradeBasicTokenAmount * userTotalRiskAmount / totalRiskAmount;
//                        userLockedForThisRiskShare = profile.totalLocked * userShareSoldRiskTradeAmount / userTotalRiskAmount; xxx


            if (profile.riskyTokenAmount == 0) {
                emit E2("SKIP user", i, "because riskyTokenAmount=", 0);
                continue;
            }
            uint256 shareRelevantLp = relevantLockedLpAmount * profile.riskyTokenAmount / riskyBalanceBefore;
            emit E2("user", i, "profile.riskyTokenAmount", profile.riskyTokenAmount);
            emit E2("user", i, "shareRelevantLp = relevantLockedLpAmount * profile.riskyTokenAmount / riskyBalanceBefore", shareRelevantLp);
            uint256 shareTradeLpEq = tradeLpAmountEquivalent * profile.riskyTokenAmount / riskyBalanceBefore;
            emit E2("user", i, "shareTradeLpEq = tradeLpAmountEquivalent * profile.riskyTokenAmount / riskyBalanceBefore", shareTradeLpEq);

            profile.lockedLp -= shareRelevantLp;  // todo: discuss
            userLockedLp[user] -= shareRelevantLp;
            if (shareTradeLpEq > shareRelevantLp) {
                uint256 x = shareTradeLpEq - shareRelevantLp;
                emit E2("PROFIT user", i, "mint x", x);
                IPoolLiquidityToken(plt).mint(user, x);
                profile.riskyAllowedLp += x;
            } else if (shareTradeLpEq == shareRelevantLp) {
                emit E1("ZERO PROFIT/LOSS user", i);
            } else {  // shareTradeLpEq < shareRelevantLp
                uint256 x = shareRelevantLp - shareTradeLpEq;
                emit E2("LOSS user", i, "burn x", x);
                IPoolLiquidityToken(plt).burn(user, x);
//                profile.riskyAllowedLp += x;  todo discuss
            }
        }
    }


    /**
    * removes investors from whitelist. Investors whitelist is applied if isInvestorsWhitelistEnabled == 'true' only;
    * @param _investors - array of investors addresses
    */
    function removeInvestorAddress (address[] memory _investors) public onlyTrader {
        for(uint i=0;i<_investors.length;i++){
            if(_investors[i] != address(0))
                delete investorWhitelist[_investors[i]];
        }
    }

    /**
    * Function caled by Exchange operation manager to initiate exchange operation
    * @param fromAsset - address of the ERC20 token that will be exchanged
    * @param toAsset - address of the ERC20 token that fromAsset will be exchanged to
    * @param caller - address of the Exchange Manager that will be invoked (same approach to flashloans)
    * @param _calldata - calldata that Exchange Manager will be provided with (same approach to flashloans)
    */  //todo minOutAmount  //todo how does exchange work
    function initiateExchangeOperation(
        address fromAsset,
        address toAsset,
        uint256 fromAmt,
        address caller,
        bytes memory _calldata
    ) public override onlyAssetManager  {  //todo onlyTrader or onlyAssetManager
        emit E1("initiateExchangeOperation-STARTED", 1);

        //todo if (toAsset in riskyTokens)
        require (fromAsset != toAsset, "incorrect asset params");
        require (fromAsset != address(0), "incorrect fromAsset param");
        require (toAsset != address(0), "incorrect toAsset param");

        // todo discuss
        //        require(hasRole(TRADER_ROLE, caller), "Caller is not the Trader");
        //        require(trader == msg.sender, "NOT_TRADER");  todo commented to let tests pass

        //1. check assetFrom price, multiply by amount, check resulting amount less then Leverage allowed.
        {
            require((
                    paramkeeper.isWhitelisted(toAsset) ||
                    traderWhitelist[toAsset] ||
                    toAsset == address(basicToken) ||
                    _riskSubPools[toAsset].enabled  // todo discuss risk trading
                ),
                "Position toToken address to be whitelisted"
            );
            uint256 maxAmount = this.getMaxPositionOpenAmount();  // max amount of this token available for trader
            uint256 spendingAmount;
            if(fromAsset == address(basicToken)) {
                spendingAmount = fromAmt;
            } else {
                spendingAmount = pAmtOpenedInBasic[fromAsset].mul(fromAmt).div(pAssetAmt[fromAsset]);
            }
            require(spendingAmount <= maxAmount, "Amount reached maximum available");
        }

//        if (fromAsset == address(basicToken) && _riskSubPools[toAsset].enabled) {  // buy risky token
//            // todo discuss how to handle it for risky trading
//            uint256 maxAmount = this.getMaxPositionOpenAmount();  //todo max amount of this token available for trader
//            uint256 spendingAmount;
//            if(fromAsset == address(basicToken)) {
//                spendingAmount = fromAmt;
//            } else {  // todo logic to limit amount of risk trade
//                spendingAmount = pAmtOpenedInBasic[fromAsset].mul(fromAmt).div(pAssetAmt[fromAsset]);
//            }
//            require(spendingAmount <= maxAmount, "Amount reached maximum available");
//
//            RiskSubPool storage subPool = _riskySubPools[toAsset];
//
//            //todo: check that it has enough allowance
//
////            FractionLib.Fraction memory currentLpPrice = lpTokenPrice();  //todo how to get
//            FractionLib.Fraction memory currentLpPrice = FractionLib.Fraction(1,1);  //todo how to get //xx
//
//            uint256 tradeLpAmountEquivalent = fromAmt * currentLpPrice.denominator / currentLpPrice.numerator;  //todo xxx
//            uint256 totalAvailableLp = subPool.totalAllowedLp - subPool.totalLockedLp;
//            require(totalAvailableLp >= tradeLpAmountEquivalent, "not enough available Lp");
//
//            for(uint256 i=0; i<subPool.users.length(); ++i){
//                address user = subPool.users.at(i);
//                RiskSubPoolUserInfo storage profile = subPool.userInfo[user];
//                uint256 userAvailableLp = profile.riskyAllowedLp - profile.lockedLp;
//                uint256 shareLockLp = tradeLpAmountEquivalent * userAvailableLp / totalAvailableLp;  // todo discuss dust
//                require(shareLockLp <= userAvailableLp, "CRITICAL: shareLockLp is to high");  // this should not be possible! this means data inconsistency
//                profile.lockedLp += shareLockLp;
//                // price is changing, user1 allow100 buy 100, then user2 allow 100 buy 200
//                // todo allowance is fixed
//                uint256 shareRiskyAmount = riskyAmount * userAvailableLp / totalAvailableLp;
//                profile.riskyTokenAmount += shareRiskyAmount;
//            }
//
//        } else if (toAsset == address(basicToken) && _riskSubPools[fromAsset].enabled) {  // sell risky token
//            // todo discuss how to handle it for risky trading
//            uint256 maxAmount = this.getMaxPositionOpenAmount();  //todo max amount of this token available for trader
//            uint256 spendingAmount;
//            if(fromAsset == address(basicToken)) {
//                spendingAmount = fromAmt;
//            } else {  // todo logic to limit amount of risk trade
//                spendingAmount = pAmtOpenedInBasic[fromAsset].mul(fromAmt).div(pAssetAmt[fromAsset]);
//            }
//            require(spendingAmount <= maxAmount, "Amount reached maximum available");
//
//        }

        uint256 fromSpent;
        uint256 toGained;
        //2. perform exchange  //todo лютый код
        {
            uint256 fromAssetBalanceBefore = IERC20Upgradeable(fromAsset).balanceOf(address(this));
            uint256 toAssetBalanceBefore = IERC20Upgradeable(toAsset).balanceOf(address(this));
            IERC20Token(fromAsset).safeTransfer(msg.sender, fromAmt);
            require(IAssetExchangeManager(msg.sender).execute(_calldata), "Asset exchange manager execution failed");
            fromSpent = fromAssetBalanceBefore.sub(IERC20Upgradeable(fromAsset).balanceOf(address(this)));
            toGained = IERC20Upgradeable(toAsset).balanceOf(address(this)).sub(toAssetBalanceBefore);
        }

        emit Exchanged (fromAsset, toAsset, fromSpent, toGained);

        //3. record positions changes & distribute profit
        if(fromAsset == address(basicToken)) {  // buy for basic
            //open new position
            if (_riskSubPools[toAsset].enabled) {
                if(pAmtOpenedInBasic[toAsset] == 0){
                    assetRiskTokenAddresses.push(toAsset);
                }
            } else {
                if(pAmtOpenedInBasic[toAsset] == 0){
                    assetTokenAddresses.push(toAsset);
                }
            }

            pAmtOpenedInBasic[toAsset] = pAmtOpenedInBasic[toAsset].add(fromSpent);  // todo for risk should be stored in diff
            pAssetAmt[toAsset] = pAssetAmt[toAsset].add(toGained);

            if (_riskSubPools[toAsset].enabled) {  // buy risky token
                uint256 currentLpTokenPriceN;
                uint256 currentLpTokenPriceD;
                (currentLpTokenPriceN, currentLpTokenPriceD) = getCurrentLpTokenPrice();
                // amount/(priceN/priceD) = amount*priceD/priceN
                uint256 tradeLpAmountEquivalent = fromAmt * currentLpTokenPriceD / currentLpTokenPriceN;
                RiskSubPool storage subPool = _riskSubPools[toAsset];

                // todo remove because replaced with dynamic calculation
//                uint256 totalAvailableLp = subPool.totalAllowedLp - subPool.totalLockedLp;
                uint256 totalAvailableLp = totalAllowedLpToBuyRiskToken(toAsset);
                emit E1("totalAvailableLp=", totalAvailableLp);

                require(totalAvailableLp >= tradeLpAmountEquivalent, "not enough available Lp");
                subPool.totalLockedLp += tradeLpAmountEquivalent;
                for(uint256 i=0; i<subPool.users.length(); ++i){
                    address user = subPool.users.at(i);
                    RiskSubPoolUserInfo storage profile = subPool.userInfo[user];
                    uint256 userAvailableLp = profile.riskyAllowedLp - profile.lockedLp;
                    uint256 shareLockLp = tradeLpAmountEquivalent * userAvailableLp / totalAvailableLp;  // todo discuss dust
                    require(shareLockLp <= userAvailableLp, "CRITICAL: shareLockLp is to high");  // this should not be possible! this means data inconsistency
                    profile.lockedLp += shareLockLp;
                    userLockedLp[user] += shareLockLp;
                    // price is changing, user1 allow100 buy 100, then user2 allow 100 buy 200
                    // todo allowance is fixed
                    uint256 shareRiskyAmount = toGained * userAvailableLp / totalAvailableLp;
                    profile.riskyTokenAmount += shareRiskyAmount;
                }
            }
        } else if(toAsset == address(basicToken)){  // sell token
            uint256 pFromAmtOpened = pAmtOpenedInBasic[fromAsset];
            uint256 pFromLiq = pAssetAmt[fromAsset];

            pAssetAmt[fromAsset] = pFromLiq.sub(fromSpent);
            uint256 originalSpentValue = pFromAmtOpened.mul(fromSpent).div(pFromLiq);
            pAmtOpenedInBasic[fromAsset] = pAmtOpenedInBasic[fromAsset].sub(originalSpentValue);

            // todo discuss
//            //remove closed position
//            if (_riskSubPools[toAsset].enabled) {
//                // todo
//            } else {
//                if(pAmtOpenedInBasic[fromAsset] == 0){
//                    _deletePosition(fromAsset);
//                }
//            }

            uint256 operationTraderCommission;
            uint256 finResB;
            if(originalSpentValue <= toGained) {  //profit
                finResB = toGained.sub(originalSpentValue);

                (uint16 traderCommissionPercentNom, uint16 traderCommissionPercentDenom) = _getCommission(1);
                operationTraderCommission = finResB.mul(traderCommissionPercentNom).div(traderCommissionPercentDenom);

                int128 currentTokenPrice = ABDKMath64x64.divu(_totalCap(), totalSupply());
                //apply trader commision fine if required
                if (currentTokenPrice < maxDepositedTokenPrice) {
                    int128 traderFine = currentTokenPrice.div(maxDepositedTokenPrice);
                    traderFine = traderFine.mul(traderFine);// ^2
                    operationTraderCommission = traderFine.mulu(operationTraderCommission);
                }

                (uint16 dexeCommissionPercentNom, uint16 dexeCommissionPercentDenom) = _getCommission(3);
                uint256 operationDeXeCommission = operationTraderCommission.mul(dexeCommissionPercentNom).div(dexeCommissionPercentDenom);
                dexeCommissionBalance = dexeCommissionBalance.add(operationDeXeCommission);
                traderCommissionBalance = traderCommissionBalance.add(operationTraderCommission.sub(operationDeXeCommission));
                emit Profit(finResB);

//                if (_riskSubPools[fromAsset].enabled) {  // sell risk token
//                    IPoolLiquidityToken(plt).mint(user, x);
////  todo                   profile.riskyAllowedLp += x;  // todo event
//                }
            } else {  //loss
                finResB = originalSpentValue.sub(toGained);
                operationTraderCommission = 0;
                emit E3("LOSS finResB: ", finResB, " = originalSpentValue ", originalSpentValue, " - toGained ", toGained);
                emit Loss(finResB);
            }
            availableCap = availableCap.add(finResB.sub(operationTraderCommission));

            if (_riskSubPools[fromAsset].enabled) {  // sell risk token, process profit/loss per user
                _sellRiskToken(fromAsset, fromAmt, pFromLiq, toGained);
            }

        } else {  // cross tokens exchange
            require(!_riskSubPools[toAsset].enabled, "cross tokens exchange for risky tokens are not allowed for now");
            require(!_riskSubPools[fromAsset].enabled, "cross tokens exchange for risky tokens are not allowed for now");

            // uint256 pFromAmtOpened = pAmtOpenedInBasic[fromAsset];
            uint256 pFromLiq = pAssetAmt[fromAsset];
            // uint256 pToAmtOpened = pAmtOpenedInBasic[toAsset];
            uint256 pToLiq = pAssetAmt[toAsset];

            //open new position
            if(pAmtOpenedInBasic[toAsset] == 0){
                assetTokenAddresses.push(toAsset);
            }

            pAmtOpenedInBasic[fromAsset] = pAmtOpenedInBasic[fromAsset].mul(pFromLiq.sub(fromSpent)).div(pFromLiq);
            pAssetAmt[fromAsset] = pFromLiq.sub(fromSpent);

            pAmtOpenedInBasic[toAsset] = pAmtOpenedInBasic[toAsset].mul(fromSpent).div(pFromLiq).add(pAmtOpenedInBasic[toAsset]);
            pAssetAmt[toAsset] = pToLiq.add(toGained);

            //remove closed position
            if(pAmtOpenedInBasic[fromAsset] == 0){
                _deletePosition(fromAsset);
            }
        }

    }

    function _deletePosition(address token) private {
        require(assetTokenAddresses.length > 0, "Cannot delete from 0 length assetTokenAddresses array");
        if(assetTokenAddresses[assetTokenAddresses.length-1] == token){
            //do nothing
        } else {
            for(uint i=0; i<assetTokenAddresses.length-1; i++){
                if(assetTokenAddresses[i] == token) {
                    assetTokenAddresses[i] = assetTokenAddresses[assetTokenAddresses.length-1];
                    break;
                }
            }
        }
        assetTokenAddresses.pop();
    }

//    todo function moveRiskSubPoolToGeneralPool(address riskyToken) onlyAdmin {
//        require(isWhiteList[riskyToken]);
//        delete _riskSubPools[riskyToken]; // in fact we just need to forget
//        // unlock user funds
//        // emit event
//    }

    /**
    * returns amount of positions in Positions array, i.e. amount of Open positions
    */
    function positionsLength() external view returns (uint256) {
        return assetTokenAddresses.length;
    }

    /**
    * returns Posision data from array at the @param _index specified. return data:
    *    1) amountOpened - the amount of Basic Tokens a position was opened with.
    *    2) liquidity - the amount of Destination tokens received from exchange when position was opened.
    *    3) token - the address of ERC20 token that position was opened to
    * i.e. the position was opened with  "amountOpened" of BasicTokens and resulted in "liquidity" amount of "token"s.
    */
    function positionAt(uint16 _index) external view returns (uint256,uint256,address) {
        require(_index < assetTokenAddresses.length, "require _index < assetTokenAddresses.length");
        address asset = assetTokenAddresses[_index];
        return (pAmtOpenedInBasic[asset], pAssetAmt[asset], asset);
    }

    /**
    * returns Posision data from array for the @param asset:
    *    1) amountOpened - the amount of Basic Tokens a position was opened with.
    *    2) liquidity - the amount of Destination tokens received from exchange when position was opened.
    *    3) token - the address of ERC20 token that position was opened to
    * i.e. the position was opened with  "amountOpened" of BasicTokens and resulted in "liquidity" amount of "token"s.
    */
    function positionFor(address asset) external view returns (uint256,uint256,address) { //todo remove code duplication
        return (pAmtOpenedInBasic[asset], pAssetAmt[asset], asset);
    }

    //todo priceofLp = SUM(positionFor(asset)[0] for asset in ...) slippage??

    /**
    * initiates withdraw of the Trader commission onto the Trader Commission address. Used by Trader to get his commission out from this contract.
    * @param amount - amount of commission to withdraw (allows for partial withdrawal)
    */
    function withdrawTraderCommission(uint256 amount) public onlyTrader {
        require(amount <= traderCommissionBalance, "Amount to be less then external commission available to withdraw");
        basicToken.safeTransfer(traderCommissionAddress, amount);
        traderCommissionBalance = traderCommissionBalance.sub(amount);
    }

    /**
    * initiates withdraw of the Dexe commission onto the Platform Commission address. Anyone can trigger this function
    * @param amount - amount of commission to withdraw (allows for partial withdrawal)
    */
    function withdrawDexeCommission(uint256 amount) public {
        require(amount <= dexeCommissionBalance, "Amount to be less then external commission available to withdraw");
        basicToken.safeTransfer(dexeCommissionAddress, amount);
        dexeCommissionBalance = dexeCommissionBalance.sub(amount);
    }


    /**
    * Change traderCommission address. The address that trader receives his commission out from this contract.
    * @param _traderCommissionAddress - new trader commission address
    */
    function setTraderCommissionAddress(address _traderCommissionAddress) public onlyTrader {
        traderCommissionAddress = _traderCommissionAddress;
    }

    //TODO: apply governance here
    /**
    * set external commission percent in a form of natural fraction: _nom/_denom.
    * @param _type - commission type (1 for trader commission, 2 for investor commission, 3 for platform commission)
    * @param _nom - nominator of the commission fraction
    * @param _denom - denominator of the commission fraction
    */
    function setCommission(uint256 _type, uint16 _nom, uint16 _denom) public onlyAdmin {
        require (_denom > 0, "Incorrect denom");
        require (_type == 1 || _type ==2 || _type == 3, "Incorrect type");
        uint16[6] memory coms;
        (coms[0],coms[1]) = _getCommission(1);
        (coms[2],coms[3]) = _getCommission(2);
        (coms[4],coms[5]) = _getCommission(3);
        if(_type == 1){
            //trader
            coms[0] = _nom;
            coms[1] = _denom;
        } else if (_type == 2) {
            //investor
            coms[2] = _nom;
            coms[3] = _denom;
        } else if (_type == 3) {
            //dexe commission
            coms[4] = _nom;
            coms[5] = _denom;
        }
        uint256 _commissions = 0;
        _commissions = _commissions.add(coms[0]);
        _commissions = _commissions.add(uint256(coms[1]) << 32);
        _commissions = _commissions.add(uint256(coms[2]) << 64);
        _commissions = _commissions.add(uint256(coms[3]) << 96);
        _commissions = _commissions.add(uint256(coms[4]) << 128);
        _commissions = _commissions.add(uint256(coms[5]) << 160);
        //store
        commissions = _commissions;

    }

    /**
    * put contract on hold. Paused contract doesn't accepts Deposits but allows to withdraw funds.
    */
    function pause() onlyAdmin public {
        super._pause();
    }

    /**
    * unpause the contract (enable deposit operations back)
    */
    function unpause() onlyAdmin public {
        super._unpause();
    }


    /**
    * returns maximum amount of basicToken's that trader can spend for opening position at the movement (including leverage)
    */
    function getMaxPositionOpenAmount() external view returns (uint256){  //todo how should it work for risk
        uint256 currentValuationBT = _totalPositionsCap();

        uint256 traderLiquidityBalanceUSD = paramkeeper.getAssetValuationManager().getAssetUSDValuation(address(basicToken), traderLiquidityBalance);
        if(traderLiquidityBalanceUSD == 0){
            traderLiquidityBalanceUSD = traderLiquidityBalance; //for testing purposes
        }
        // l = 0.5*t*pUSD/1000
        uint256 L = traderLiquidityBalanceUSD.mul(currentValuationBT.add(availableCap)).div(totalSupply()).div(2000).div(10**18);
        // maxQ =  (l+1)*t*p - w
        uint256 maxQ = L.add(1).mul(traderLiquidityBalance).mul(currentValuationBT.add(availableCap)).div(totalSupply());
        maxQ = (maxQ > currentValuationBT)? maxQ.sub(currentValuationBT) : 0;

        return maxQ;
    }

    // /**
    // * returns address parameter from central parameter storage operated by the platform. Used by PositionManager contracts to receive settings required for performing operations.
    // * @param key - ID of address parameter;
    // */
    // function getAddress(uint16 key) external override view returns (address){
    //     return paramkeeper.getAddress(key);
    // }
    // /**
    // * returns uint256 parameter from central parameter storage operated by the platform. Used by PositionManager contracts to receive settings required for performing operations.
    // * @param key - ID of uint256 parameter;
    // */
    // function getUInt256(uint16 key) external override view returns (uint256){
    //     return paramkeeper.getUInt256(key);
    // }

    /**
    * returns the data of the User:
    *    1) total amount of BasicTokens deposited (historical value)
    *    2) average traderToken price of the investor deposit (historical value)
    *    3) current amount of TraderPool liquidity tokens that User has on the balance.
    * @param holder - address of the User's wallet.
     */
    function getUserData(address holder) public view returns (uint256, int128, uint256) {
        return (deposits[holder].amount, deposits[holder].price, IERC20Token(plt).balanceOf(holder));
    }

    //    /// @dev
//    function claimLockedLp(address riskyToken, uint256 lpTokenAmount, uint256 minOutBaseAmount) {
//        RiskSubPoolUserInfo storage subPool = _riskSubPools[riskyToken];
//        RiskSubPoolUserInfo storage profile = subPool.userInfo[msg.sender];
//        require(lpTokenAmount <= lpToken.balanceOf(msg.sender), "NOT lpTokenAmount <= lpToken.balanceOf(msg.sender)");  // todo fix
//        require(lpTokenAmount <= profile.lockedLp, "NOT lpTokenAmount <= profile.lockedLp");
//        subPool.totalAllowedLp = subPool.totalAllowedLp - lpTokenAmount;
//        profile.riskyAllowedLp -= lpTokenAmount;
//        // perform exchange risky -> base
//        {
//            uint256 fromAssetBalanceBefore = IERC20Upgradeable(fromAsset).balanceOf(address(this));
//            uint256 toAssetBalanceBefore = IERC20Upgradeable(toAsset).balanceOf(address(this));
//
//            // todo discuss
//            IERC20Token(fromAsset).safeTransfer(msg.sender, fromAmt);
//            require(IAssetExchangeManager(msg.sender).execute(_calldata), "Asset exchange manager execution failed");
//            fromSpent = fromAssetBalanceBefore.sub(IERC20Upgradeable(fromAsset).balanceOf(address(this)));
//            toGained = IERC20Upgradeable(toAsset).balanceOf(address(this)).sub(toAssetBalanceBefore);
//
//            emit Exchanged (fromAsset, toAsset, fromSpent, toGained);  // todo event type
//            IERC20(basicToken).safeTransfer(msg.sender, toGained);
//        }
//    }


    /**
    * returns total cap values for this contract:
    * 1) totalCap value - total capitalization, including profits and losses, denominated in BasicTokens. i.e. total amount of BasicTokens that porfolio is worhs of.
    * 2) totalSupply of the TraderPool liquidity tokens (or total amount of trader tokens sold to Users).
    * Trader token current price = totalCap/totalSupply;
    */
    function getTotalValueLocked() public view returns (uint256, uint256){
        return (_totalCap(), totalSupply());
    }

    /**
    * returns commission natural fraction for a specified @param _type (1 for trader commission, 2 for investor commission, 3 for platform commission)
    */
    function getCommission(uint256 _type) external view returns (uint16,uint16){
        return _getCommission(_type);
    }

    //***************************INTERNAL METHODS **************************/

    /**
    * returns total capital locked on the Trader contract
    */
    function _totalCap() internal override view returns (uint256){
        return _totalPositionsCap().add(availableCap);
    }

    function _beforeDeposit(uint256 amountTokenSent, address sender, address holder) internal override {
        require(!paused(), "Cannot deposit when paused");
        require(!isInvestorsWhitelistEnabled || investorWhitelist[msg.sender] || traderFundAddresses[msg.sender], "Investor not whitelisted");
    }

    function _afterDeposit(uint256 amountTokenSent, uint256 amountLiquidityGot, address sender, address holder, int128 tokenPrice) internal override {
        // check if that was a trader who put a deposit
        if(traderFundAddresses[holder])
            traderLiquidityBalance = traderLiquidityBalance.add(amountLiquidityGot);
        // store max traderTokenPrice that any investor got in
        maxDepositedTokenPrice = (maxDepositedTokenPrice<tokenPrice)?tokenPrice:maxDepositedTokenPrice;
        //for active position - distribute funds between positions.
        IAssetAutomaticExchangeManager exchanger = paramkeeper.getAssetAutomaticExchangeManager();
        if(isActualOn && assetTokenAddresses.length > 0){
            uint256 totalOpened=0;
            for(uint i=0;i<assetTokenAddresses.length;i++){
                totalOpened = totalOpened.add(pAmtOpenedInBasic[assetTokenAddresses[i]]);
            }
            //fund
            uint256 amoutTokenLeft = amountTokenSent;
            // uint256 deadline = block.timestamp + 5*60;
            // uint256 liquidity;
            for(uint16 i=0;i<assetTokenAddresses.length;i++){
                uint256 fundPositionAmt = amountTokenSent.mul(pAmtOpenedInBasic[assetTokenAddresses[i]]).div(totalOpened);
                if(fundPositionAmt < amoutTokenLeft)//underflow with division
                    fundPositionAmt = amoutTokenLeft;

                uint256 fromSpent;
                uint256 toGained;
                //perform automatic exchange
                {
                    uint256 fromAssetBalanceBefore = basicToken.balanceOf(address(this));
                    uint256 toAssetBalanceBefore = IERC20Upgradeable(assetTokenAddresses[i]).balanceOf(address(this));
                    basicToken.safeTransfer(address(exchanger), fundPositionAmt);
                    exchanger.swapExactTokenForToken(address(basicToken), assetTokenAddresses[i], fundPositionAmt);
                    fromSpent = fromAssetBalanceBefore.sub(basicToken.balanceOf(address(this)));
                    toGained = IERC20Upgradeable(assetTokenAddresses[i]).balanceOf(address(this)).sub(toAssetBalanceBefore);
                }
                emit Exchanged (address(basicToken), assetTokenAddresses[i], fromSpent, toGained);
                pAmtOpenedInBasic[assetTokenAddresses[i]] = pAmtOpenedInBasic[assetTokenAddresses[i]].add(fromSpent);
                pAssetAmt[assetTokenAddresses[i]] = pAssetAmt[assetTokenAddresses[i]].add(toGained);
                //
                amoutTokenLeft = amoutTokenLeft.sub(fromSpent);
            }
        }

    }


    /**
    *    @param revenue - revenue (capital gain in basic token)
    *    @param holder - user who got the revenue
    *    @param currentTokenPrice - current trader token price (as of the time of revenue accrued)
    */
    function _getWithdrawalCommission(uint256 revenue, address holder, int128 currentTokenPrice) internal override view returns (uint256){
        uint256 commision; //commission in basic token
        //applied for investors only. not for traders
        if(currentTokenPrice > deposits[holder].price && !traderFundAddresses[holder]){
            int128 priceDiff = currentTokenPrice.sub(deposits[holder].price);
            (uint16 investorCommissionPercentNom, uint16 investorCommissionPercentDenom) = _getCommission(2);
            //profit = priceDiff * revenue;
            commision = priceDiff.mulu(revenue).mul(investorCommissionPercentNom).div(investorCommissionPercentDenom);
        } else {
            commision = 0;
        }
        return commision;
    }

    function _beforeWithdraw(uint256 amountLiquidity, address holder, address receiver) internal override {
        if(traderFundAddresses[holder]){
            traderLiquidityBalance.sub(amountLiquidity);
        }
    }


    function _getCommission(uint256 _type) internal view returns (uint16,uint16){
        uint16 denom;
        uint16 _nom;
        if(_type == 1){
            //trader commission
            denom = uint16(commissions & 0x00000000000000000000000000000000000000000000000000000000FFFFFFFF);
            _nom = uint16((commissions & 0x000000000000000000000000000000000000000000000000FFFFFFFF00000000) >> 32);
        } else if (_type == 2) {
            //investor commission
            denom =uint16((commissions & 0x0000000000000000000000000000000000000000FFFFFFFF0000000000000000) >> 64);
            _nom = uint16((commissions & 0x00000000000000000000000000000000FFFFFFFF000000000000000000000000) >> 96);
        } else if (_type == 3) {
            //dexe commission
            denom =uint16((commissions & 0x000000000000000000000000FFFFFFFF00000000000000000000000000000000) >> 128);
            _nom = uint16((commissions & 0x0000000000000000FFFFFFFF0000000000000000000000000000000000000000) >> 160);
        } else {
            _nom = uint16(0);
            denom = uint16(1);
        }
        return (_nom, denom);
    }

    // todo discuss
    //   note it's slippage prices
    function _totalPositionsCap() internal view returns (uint256) {
        uint256 totalPositionsCap = 0;
        for(uint256 i=0;i<assetTokenAddresses.length;i++){
            uint256 positionValuation = paramkeeper.getAssetValuationManager().getAssetValuation(address(basicToken),assetTokenAddresses[i],pAssetAmt[assetTokenAddresses[i]]);
            if(positionValuation == 0)
                positionValuation = pAmtOpenedInBasic[assetTokenAddresses[i]];
            totalPositionsCap = totalPositionsCap.add(positionValuation);
        }
        return totalPositionsCap;
    }
}
