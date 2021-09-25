// SPDX-License-Identifier: MIT
pragma solidity 0.6.8;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "./pancake/interfaces/IPancakeRouter01.sol";
import "./pancake/interfaces/IPancakePair.sol";
import "./interfaces/IAssetValuationManager.sol";

contract PancakePathFinder is Initializable, IAssetValuationManager{
  using SafeMathUpgradeable for uint256;

  address[] internal intermediateTokens;

  function initialize() public initializer {
    intermediateTokens.push(IPancakeRouter01(pancakeRouter()).WETH()); //wbnb
    intermediateTokens.push(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56); //busd
    intermediateTokens.push(0x55d398326f99059fF775485246999027B3197955); //usdt
  }

  function findPath(address fromToken, address toToken) public view returns (address[] memory path) {
    (, path) = evaluatePath(fromToken, toToken, 1000);
  }

  function evaluate(address fromToken, address toToken, uint256 fromTokenAmt) public view returns (uint256, address[] memory) {
    return evaluatePath(fromToken, toToken, fromTokenAmt);
  }

  function getAssetValuation(address basicToken, address assetToken, uint256 assetAmount) public override view returns (uint256 valuation) {
      (valuation, ) = evaluatePath(assetToken, basicToken, assetAmount);
  }

  function getAssetUSDValuation(address assetToken, uint256 assetTokenAmt) public override view returns (uint256 assetTokenOut) {
    address usdPeggedCoinAddress = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56; //busd
    if(assetToken == usdPeggedCoinAddress){
      assetTokenOut = assetTokenAmt;
    }
    else {
     (assetTokenOut,) = evaluatePath(assetToken, usdPeggedCoinAddress, assetTokenAmt);
    }
  }

  function pancakePositionCap(address basicToken, address toToken, uint256 liquidity) internal view returns (uint256){
      (uint reserveB, uint reserveA) = getReserves(IPancakeRouter01(pancakeRouter()).factory(), basicToken, toToken);
      return getAmountOut(liquidity, reserveA, reserveB);
  }

  function pancakeRouter() internal view returns (address){
      return 0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F;
  }

  function pancakeFactory() internal view returns (address){
      return IPancakeRouter01(pancakeRouter()).factory();
  } 

  function evaluatePath(address fromToken, address toToken, uint256 fromTokenAmt) internal view returns (uint256, address[] memory) {
    if(fromToken == toToken)
      return (fromTokenAmt, new address[](0));
    address[] memory path = new address[](2);
    path[0] = fromToken;
    path[1] = toToken;
    uint256 resultingAmt = getAmountsOut(pancakeFactory(),fromTokenAmt,path)[1];

    address[] memory internalPath = new address[](3);
    internalPath[0] = fromToken;
    internalPath[2] = toToken;
    for(uint i =0;i < intermediateTokens.length; i++){
      if(fromToken != intermediateTokens[i] && toToken!= intermediateTokens[i]){
        internalPath[1] = intermediateTokens[i];
        uint256 internalResultAmt = getAmountsOut(pancakeFactory(),fromTokenAmt,internalPath)[internalPath.length-1];
        if(internalResultAmt > resultingAmt){
          resultingAmt = internalResultAmt;
          path = new address[](3);
          path[1] = intermediateTokens[i];
        }
      }
    }

    if(path.length == 3 && resultingAmt>0) { //avoid trying path[4] if intermediate was not successful && direct path gives non zero result
      internalPath = new address[](4);
      internalPath[0] = fromToken;
      internalPath[3] = toToken;
      for(uint i = 0;i < intermediateTokens.length; i++){
        for (uint j = 0; j < intermediateTokens.length; j++){
          if( i != j && fromToken != intermediateTokens[i] && toToken!= intermediateTokens[i] && fromToken != intermediateTokens[j] && toToken != intermediateTokens[j]) {
            internalPath[1] = intermediateTokens[i];
            internalPath[2] = intermediateTokens[j];
            uint256 internalResultAmt = getAmountsOut(pancakeFactory(),fromTokenAmt,internalPath)[internalPath.length-1];
            if(internalResultAmt > resultingAmt){
              resultingAmt = internalResultAmt;
              path = new address[](4);
              path[1] = intermediateTokens[i];
              path[2] = intermediateTokens[j];
            }
          }
        }
      }
    }

    path[0] = fromToken;
    path[path.length-1] = toToken;

    return (resultingAmt,path);
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


    // fetches and sorts the reserves for a pair
    function getReserves(address factory, address tokenA, address tokenB) internal view returns (uint reserveA, uint reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        address pairAddress = pairFor(factory, tokenA, tokenB);
        if(!AddressUpgradeable.isContract(pairAddress)){
          (reserveA, reserveB) = (0,0);
        } else{ 
          (uint reserve0, uint reserve1,) = IPancakePair(pairFor(factory, tokenA, tokenB)).getReserves();
          (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
        }
    }

        // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        // require(amountIn > 0, 'PancakeLibrary: INSUFFICIENT_INPUT_AMOUNT');
        // require(reserveIn > 0 && reserveOut > 0, 'PancakeLibrary: INSUFFICIENT_LIQUIDITY');
        if(amountIn>0 && reserveIn > 0 && reserveOut > 0 ){
          uint amountInWithFee = amountIn.mul(998);
          uint numerator = amountInWithFee.mul(reserveOut);
          uint denominator = reserveIn.mul(1000).add(amountInWithFee);
          amountOut = numerator / denominator;
        }else {
          amountOut = 0;
        }
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(address factory, uint amountIn, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'PancakeLibrary: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) {
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }
}
