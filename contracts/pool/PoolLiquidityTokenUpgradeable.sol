pragma solidity 0.6.8;


import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "../interfaces/IPoolLiquidityToken.sol";

contract PoolLiquidityTokenUpgradeable is ERC20Upgradeable, OwnableUpgradeable, IPoolLiquidityToken {

    // uint256 public maxPoolTotalSupply;
    bool public fixedSupply;

    function initialize(address _owner, uint256 _maxPoolTotalSupply, string memory name_, string memory symbol_) public override initializer {
        __ERC20_init(name_, symbol_);
        __Ownable_init_unchained();
        __PoolLiquidityTokenUpgradeable_init_unchained(_owner, _maxPoolTotalSupply);
    }

    function __PoolLiquidityTokenUpgradeable_init_unchained(address _owner, uint256 _maxPoolTotalSupply) internal initializer {
        transferOwnership(_owner);
        if(_maxPoolTotalSupply > 0){
            fixedSupply = true;
            _mint(address(this), _maxPoolTotalSupply);
        }
    }

    function mint(address to, uint256 amount) public override onlyOwner{
        if(fixedSupply){
            _transfer(address(this), to, amount);
        }else {
            _mint(to, amount);
        }
        // require (maxPoolTotalSupply == 0 || totalSupply() <= maxPoolTotalSupply, "Pool reached its max allowed liquidity");   
    }

    function burn(address from, uint256 amountLiquidity) public override onlyOwner{
        if(fixedSupply){
            _transfer(from, address(this), amountLiquidity);
        } else {
            _burn(from, amountLiquidity);
        }
        
    } 
}