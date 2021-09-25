pragma solidity 0.6.8;
//pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import {FractionLib} from "../FractionLib.sol";

contract SwapperMock {
    using SafeERC20 for IERC20;

    mapping(address => mapping(address => FractionLib.Fraction)) internal prices;

    function priceOf(address tokenFrom, address tokenTo) public view returns(FractionLib.Fraction memory result) {
        result = prices[tokenFrom][tokenTo];
    }

    // todo slippage
    function setPrice(address tokenFrom, address tokenTo, uint256 numerator, uint256 denominator) external {
        require(numerator > 0);
        require(denominator > 0);
        prices[tokenFrom][tokenTo] = FractionLib.Fraction(numerator, denominator);
        prices[tokenTo][tokenFrom] = FractionLib.Fraction(denominator, numerator);  // todo discuss
    }

    function swap(
        address tokenFrom, address tokenTo, uint256 amountFrom, uint256 minAmountTo
    ) public returns(uint256) {
        FractionLib.Fraction memory f = prices[tokenFrom][tokenTo];
        require(f.denominator != 0, "zero denominator");
        uint256 amountTo = amountFrom * f.numerator / f.denominator;
        require(amountTo >= minAmountTo, "small amountTo");
        IERC20(tokenFrom).safeTransferFrom(msg.sender, address(this), amountFrom);
        IERC20(tokenTo).safeTransfer(msg.sender, amountTo);
        return amountTo;
    }
}
