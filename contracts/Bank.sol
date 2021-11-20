//SPDX-License-Identifier: Unlicense
pragma solidity 0.7.0;

import "./interfaces/IBank.sol";
import "./interfaces/IPriceOracle.sol";

contract Bank is IBank {
    address priceOracle;
    address hakToken;
    
    mapping(address => uint256) private customerHaks;
    mapping(address => uint256) private custormerEths;

    constructor(address _priceOracle, address _hakToken) {
        priceOracle = _priceOracle;
        hakToken = _hakToken;
    }
    
    function deposit(address token, uint256 amount)
        payable
        external
        override
        returns (bool) {}

    function withdraw(address token, uint256 amount)
        external
        override
        returns (uint256) {}

    function borrow(address token, uint256 amount)
        external
        override
        returns (uint256) {}

    function repay(address token, uint256 amount)
        payable
        external
        override
        returns (uint256) {}

    function liquidate(address token, address account)
        payable
        external
        override
        returns (bool) {}

    function getCollateralRatio(address token, address account)
        view
        public
        override
        returns (uint256) {}

    function getBalance(address token)
        view
        public
        override
        returns (uint256) {
            if (token == hakToken) {
                return customerHaks[msg.sender];
            } else {
                return custormerEths[msg.sender];
            }
        }
}
