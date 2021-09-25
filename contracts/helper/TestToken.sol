pragma solidity 0.6.8;

import "../token/ERC20/ERC20.sol";
import "../token/ERC20/ERC20Burnable.sol";
import "../math/SafeMath.sol";

contract TestToken is ERC20, ERC20Burnable {

    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) public {
        _mint(msg.sender, 1000*1000*1000*1000*1000*1000 * (10 ** uint(decimals())));  // 1 Quintillion * decimals tokens
    }

}