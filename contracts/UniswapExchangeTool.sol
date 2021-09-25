
pragma solidity 0.6.8;

import "./math/SafeMath.sol";
import "./token/ERC20/IERC20.sol";
import "./token/ERC20/SafeERC20.sol";
import "./interfaces/IAssetExchangeManager.sol";
import "./interfaces/ITraderPool.sol";
import "./uniswap/RouterInterface.sol";
import "./uniswap/UniswapV2Library.sol";

/**
    UNISWAP based example. 
 */
contract UniswapExchangeTool is IAssetExchangeManager {
    
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    constructor() public {
    }


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
        IERC20(path[0]).safeIncreaseAllowance(uniswapRouter(), amountIn);
        uint[] memory out = IUniswapV2Router01(uniswapRouter()).swapExactTokensForTokens(
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
