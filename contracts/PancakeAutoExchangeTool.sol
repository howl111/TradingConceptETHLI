
pragma solidity 0.6.8;

import "./math/SafeMath.sol";
import "./token/ERC20/IERC20.sol";
import "./token/ERC20/SafeERC20.sol";
import "./interfaces/IAssetAutomaticExchangeManager.sol";
import "./interfaces/ITraderPool.sol";
import "./pancake/interfaces/IPancakeRouter01.sol";
import "./PancakePathFinder.sol";

/**
    UNISWAP based example. 
 */
contract PancakeAutoExchangeTool is IAssetAutomaticExchangeManager {
    
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    PancakePathFinder internal pathfinder;

    constructor(address _pathfinder) public {
        pathfinder = PancakePathFinder(_pathfinder);
    }

    function swapExactTokenForToken(
        address fromToken, 
        address toToken, 
        uint256 amountFrom) public override
        returns (uint256){

    (,address[] memory path) = pathfinder.evaluate(fromToken, toToken, amountFrom);
    uint deadline = block.timestamp.add(86400);
        
    IERC20(path[0]).safeIncreaseAllowance(pancakeRouter(), amountFrom);
    uint[] memory out = IPancakeRouter01(pancakeRouter()).swapExactTokensForTokens(
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
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'PancakeLibrary: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'PancakeLibrary: ZERO_ADDRESS');
    }

   // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                hex'd0d4c4cd0848c93cb4fd1f498d7013ee6bfb25783ea21593d5834f5d250ece66' // init code hash
            ))));
    }

    function pancakeRouter() internal view returns (address){
      return 0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F;
    }

}
