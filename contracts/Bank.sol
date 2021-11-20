//SPDX-License-Identifier: Unlicense
pragma solidity 0.7.0;

import "./interfaces/IBank.sol";
import "./interfaces/IPriceOracle.sol";
import {DSMath} from "./libraries/Math.sol";
    
contract Bank is IBank {
    struct Customer {
        IBank.Account ethAccount;
        IBank.Account hakAccount;
        uint256 borrowed;
        uint256 borrowBlock;
    }

    struct SimpleBank {
        address bank;
        uint256 ethAmount;
        uint256 hakAmount;
    }

    IPriceOracle priceOracle;
    address hakToken;
    address ethToken = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    SimpleBank bank;
    
    mapping(address => Customer) customerAccounts;

    constructor(address _priceOracle, address _hakToken) {
        priceOracle = IPriceOracle(_priceOracle);
        hakToken = _hakToken;
        bank = SimpleBank(msg.sender, 0, 0);
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
        returns (uint256) {
            if (token != hakToken) {
                revert('token not supported');
            }
            uint256 ethHakPrice = priceOracle.getVirtualPrice(hakToken);
            if (customerAccounts[account].hakAccount.deposit == 0) {
                return 0;
            }
            if (customerAccounts[account].borrowed == 0) {
                return type(uint256).max;
            }
            uint256 borrowInterest = DSMath.wmul(DSMath.wdiv(
                DSMath.sub(block.number, customerAccounts[account].borrowBlock), 100), 5);
            uint256 borrowVal = DSMath.add(customerAccounts[account].borrowed,
                DSMath.wmul(borrowInterest, customerAccounts[account].borrowed));
            uint256 depositVal = DSMath.wmul(DSMath.add(customerAccounts[msg.sender].hakAccount.deposit, 
                customerAccounts[msg.sender].hakAccount.interest), ethHakPrice);
            return DSMath.wdiv(depositVal, borrowVal);
                
        }

    function getBalance(address token)
        view
        public
        override
        returns (uint256) {
            if (token == hakToken) {
                return DSMath.add(customerAccounts[msg.sender].hakAccount.deposit, 
                    customerAccounts[msg.sender].hakAccount.interest);
            } else if (token == ethToken) {
                return DSMath.add(customerAccounts[msg.sender].ethAccount.deposit, 
                    customerAccounts[msg.sender].ethAccount.interest);
            } else {
                revert('token not supported');
            }
        }
}
