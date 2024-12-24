//SPDX-License-Identifier:MIT

pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
/**
 * @title DecentralizedStableCoin
 * @author RealGC
 * Collateral:exogenous(ETH&BTC)
 * Miniting:Algorithmic
 * Relative Stability:Pegged to USD
 * This is the contract meant to be governed by DSCEngine.This contract is just the ERC20 implementation of our stablecoin system.
 */

contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__BurnAmountMustBeGreaterThanZero();
    error DecentralizedStableCoin__BurnAmountMustBeLessThanBalance();
    error DecentralizedStableCoin__NotZeroAddress();
    error DecentralizedStableCoin__MintAmountMustBeGreaterThanZero();

    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralizedStableCoin__BurnAmountMustBeGreaterThanZero();
        }
        if (balance < _amount) {
            revert DecentralizedStableCoin__BurnAmountMustBeLessThanBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) revert DecentralizedStableCoin__NotZeroAddress();
        if (_amount <= 0) revert DecentralizedStableCoin__MintAmountMustBeGreaterThanZero();
        _mint(_to, _amount);
        return true;
    }
}
