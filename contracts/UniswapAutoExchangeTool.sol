
pragma solidity 0.6.8;

import "./math/SafeMath.sol";
import "./token/ERC20/IERC20.sol";
import "./token/ERC20/SafeERC20.sol";
import "./interfaces/IAssetAutomaticExchangeManager.sol";
import "./interfaces/ITraderPool.sol";
import "./uniswap/RouterInterface.sol";
import "./uniswap/UniswapV2Library.sol";
import "./UniswapPathFinder.sol";

/**
    UNISWAP based example. 
 */
contract UniswapAutoExchangeTool is IAssetAutomaticExchangeManager {
    
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    UniswapPathFinder internal pathfinder;

    constructor(address _pathfinder) public {
        pathfinder = UniswapPathFinder(_pathfinder);
    }

    function swapExactTokenForToken(
        address fromToken, 
        address toToken, 
        uint256 amountFrom) public override
        returns (uint256){

    (,address[] memory path) = pathfinder.evaluate(fromToken, toToken, amountFrom);
    uint deadline = block.timestamp.add(86400);
        
    IERC20(path[0]).safeIncreaseAllowance(uniswapRouter(), amountFrom);
    uint[] memory out = IUniswapV2Router01(uniswapRouter()).swapExactTokensForTokens(
        amountFrom,
        0,
        path,
        msg.sender,
        deadline
    );
    //return back non spent original tokens
    uint256 backTokenAmt = amountFrom.sub(out[0]);
    if(backTokenAmt > 0)
        IERC20(path[0]).safeTransfer(msg.sender, backTokenAmt);

    return out[1];
    }

     // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function _sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'UniswapV2Library: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'UniswapV2Library: ZERO_ADDRESS');
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function _pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f' // init code hash
            ))));
    }

    function uniswapRouter() internal view returns (address){
        return 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    }

}
