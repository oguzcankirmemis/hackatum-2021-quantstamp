//SPDX-License-Identifier: Unlicense
pragma solidity 0.7.0;

import "./interfaces/IBank.sol";
import "./interfaces/IPriceOracle.sol";
import {DSMath} from "./libraries/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
    
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
    
    IERC20 hak;
    IERC20 eth;
    
    SimpleBank bank;
    
    mapping(address => Customer) customerAccounts;

    constructor(address _priceOracle, address _hakToken) {
        priceOracle = IPriceOracle(_priceOracle);
        hakToken = _hakToken;
        bank = SimpleBank(msg.sender, 0, 0);
        hak = IERC20(hakToken);
        eth = IERC20(ethToken);
    }
    
    function deposit(address token, uint256 amount)
        payable
        external
        override
        returns (bool) {
            Customer storage customer = customerAccounts[msg.sender];
            if (token == hakToken) {
                hak.transferFrom(msg.sender, bank.bank, amount);
                customer.hakAccount.deposit = DSMath.add(customer.hakAccount.deposit, amount);
                bank.hakAmount = DSMath.add(bank.hakAmount, amount);
                emit Deposit(msg.sender, token, amount);
                return true;
            } else if(token == ethToken) {
                require(amount == msg.value, "Amount and value cannot be different!");
                customer.ethAccount.deposit = DSMath.add(customer.ethAccount.deposit, amount);
                bank.ethAmount = DSMath.add(bank.ethAmount, amount);
                emit Deposit(msg.sender, token, amount);
                return true;
            }
            revert("token not supported");
        }

    function withdraw(address token, uint256 amount)
        external
        override
        returns (uint256) {
            Customer storage customer = customerAccounts[msg.sender];
            if (token == hakToken) {
                require(customer.hakAccount.deposit != 0, "no balance");
                uint256 hakInterest = DSMath.wmul(
                    DSMath.wdiv(DSMath.sub(block.number, customer.hakAccount.lastInterestBlock), 100), 3);
                customer.hakAccount.lastInterestBlock = block.number;
                uint256 hakInterestVal = DSMath.wmul(customer.hakAccount.deposit, hakInterest);
                uint256 toSend = DSMath.add(amount, hakInterestVal);
                if (amount > customer.hakAccount.deposit) {
                    revert('amount bigger than deposit');
                }
                if (toSend > bank.hakAmount) {
                    revert('hak bankrupt');
                }
                bank.hakAmount = DSMath.sub(bank.hakAmount, toSend);
                customer.hakAccount.deposit = DSMath.sub(customer.hakAccount.deposit, amount);
                payable(msg.sender).transfer(toSend);
                emit Withdraw(msg.sender, token, toSend);
                return toSend;
            } else if (token == ethToken) {
                require(customer.ethAccount.deposit != 0, "no balance");
                uint256 ethInterest = DSMath.wmul(
                    DSMath.wdiv(DSMath.sub(block.number, customer.ethAccount.lastInterestBlock), 100), 3);
                customer.ethAccount.lastInterestBlock = block.number;
                uint256 ethInterestVal = DSMath.wmul(customer.ethAccount.deposit, ethInterest);
                uint256 toSend = DSMath.add(amount, ethInterestVal);
                if (amount > customer.ethAccount.deposit) {
                    revert('amount bigger than deposit');
                }
                if (toSend > bank.ethAmount) {
                    revert('eth bankrupt');
                }
                bank.ethAmount = DSMath.sub(bank.ethAmount, toSend);
                customer.ethAccount.deposit = DSMath.sub(customer.ethAccount.deposit, amount);
                payable(msg.sender).transfer(toSend);
                emit Withdraw(msg.sender, token, toSend);
                return toSend;
            }
            revert("token not supported");
        }

    function borrow(address token, uint256 amount)
        external
        override
        returns (uint256) {
            if (token != ethToken) {
                revert('token not supported');
            }
            address payable account = msg.sender;
            if (customerAccounts[account].borrowed == 0) {
                customerAccounts[account].borrowBlock = block.number;
            }
            uint256 oldBorrowed = customerAccounts[account].borrowed;
            customerAccounts[account].borrowed = amount;
            uint256 cRatio = getCollateralRatio(hakToken, account);
            if (cRatio < 15000) {
                customerAccounts[account].borrowed = oldBorrowed;
                revert('collateral ratio less than 150%');
            }
            uint256 ethHakPrice = priceOracle.getVirtualPrice(hakToken);
            if (amount == 0) {
                uint256 d = customerAccounts[account].hakAccount.deposit;
                uint256 d_i = customerAccounts[account].hakAccount.interest;
                uint256 b_i = DSMath.wmul(DSMath.wdiv(
                    DSMath.sub(block.number, customerAccounts[account].borrowBlock), 100), 5);
                uint256 maxBorrow = DSMath.wdiv(DSMath.wdiv(
                    DSMath.wmul(DSMath.wmul(DSMath.add(d, d_i), ethHakPrice), 10000), 15000), DSMath.add(1, b_i));
                uint256 toSend = DSMath.sub(maxBorrow, customerAccounts[account].borrowed);
                if (toSend > bank.ethAmount) {
                    revert('eth borrow bankrupt');
                }
                bank.ethAmount = DSMath.sub(bank.ethAmount, toSend);
                customerAccounts[account].borrowed = maxBorrow;
                account.transfer(toSend);
                emit Borrow(account, ethToken, toSend, 15000);
            } else {
                account.transfer(amount);
                emit Borrow(account, ethToken, amount, cRatio);
            }
            return getCollateralRatio(hakToken, account);
        }

    function repay(address token, uint256 amount)
        payable
        external
        override
        returns (uint256) {
            if (token != ethToken) {
                revert('token not supported');
            }
            if (amount != msg.value) {
                revert('amount not equal to sent');
            }
            bank.ethAmount = DSMath.add(bank.ethAmount, msg.value);
            address account = msg.sender;
            uint256 borrowInterest = DSMath.wmul(DSMath.wdiv(
                DSMath.sub(block.number, customerAccounts[account].borrowBlock), 100), 5);
            uint256 borrowInterestVal = DSMath.wmul(borrowInterest, customerAccounts[account].borrowed);
            uint256 remaining = DSMath.sub(amount, borrowInterestVal);
            customerAccounts[account].borrowed = DSMath.sub(customerAccounts[account].borrowed, remaining);
            emit IBank.Repay(account, token, customerAccounts[account].borrowed);
            return customerAccounts[account].borrowed;
        }

    function liquidate(address token, address account)
        payable
        external
        override
        returns (bool) {
            if (token != hakToken) {
                revert('token not supported');
            }
            if (getCollateralRatio(token, account) >= 15000) {
                revert('cannot liquidate (collateral ratio >= 150%');
            }
            address payable payer = msg.sender;
            uint256 borrowInterest = DSMath.wmul(DSMath.wdiv(
                DSMath.sub(block.number, customerAccounts[account].borrowBlock), 100), 5);
            uint256 borrowVal = DSMath.add(customerAccounts[account].borrowed,
                DSMath.wmul(borrowInterest, customerAccounts[account].borrowed));
            if (borrowVal > msg.value) {
                revert('cannot liquidate (debt > deposit');
            }
            uint256 sentBack = DSMath.sub(msg.value, borrowVal);
            bank.ethAmount = DSMath.add(bank.ethAmount, borrowVal);
            payer.transfer(sentBack);
            customerAccounts[account].borrowed = 0;
            customerAccounts[payer].hakAccount.deposit = DSMath.add(
                customerAccounts[payer].hakAccount.deposit, customerAccounts[account].hakAccount.deposit);
            customerAccounts[account].hakAccount.deposit = 0;
            emit IBank.Liquidate(
                payer, account, token, customerAccounts[account].hakAccount.deposit, sentBack);
            return true;
        }

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
