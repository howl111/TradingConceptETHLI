

pragma solidity 0.6.8;

import "./math/SafeMath.sol";
import "./token/ERC20/IERC20.sol";
import "./token/ERC20/SafeERC20.sol";
import "./interfaces/IAssetExchangeManager.sol";
import "./interfaces/ITraderPool.sol";
import "./pancake/interfaces/IPancakeRouter01.sol";

/**
    UNISWAP based example. 
 */
contract PancakeExchangeTool is IAssetExchangeManager {
    
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    constructor() public {
    }

    /** Exchanges tokens from Trader pool
    * @param traderPool - trader pool address
    * @param amountIn - amount of tokens to swap
    * @param amountOutMin - minimum amount of result tokens to receive
    * @param path - pancake swap exchange path
    * @param deadline - pancake transaction dealine
    */
    function swapExactTokensForTokens(
        address traderPool,
        uint amountIn,
        uint amountOutMin,
        address[] memory path,
        uint deadline
    ) public {
        bytes memory data = abi.encode(amountIn, amountOutMin, traderPool, deadline, path);
        // function initiateExchangeOperation(address fromAsset, address toAsset, uint256 fromAmt, address caller, bytes memory _calldata)
        address fromAsset = path[0];
        address toAsset = path[path.length-1];
        ITraderPool(traderPool).initiateExchangeOperation(fromAsset,toAsset,amountIn,msg.sender, data);
    }

    function execute(bytes memory _calldata) public override returns (bool){
        (uint256 amountIn, uint256 amountOutMin, address to, uint deadline, address[] memory path) = abi.decode(_calldata, (uint256, uint256, address, uint, address[]));
        IERC20(path[0]).safeIncreaseAllowance(pancakeRouter(), amountIn);
        uint[] memory out = IPancakeRouter01(pancakeRouter()).swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            to,
            deadline
        );
        //return back non spent original tokens
        uint256 backTokenAmt = amountIn.sub(out[0]);
        if(backTokenAmt > 0)
            IERC20(path[0]).safeTransfer(to, backTokenAmt);

        return true;
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
