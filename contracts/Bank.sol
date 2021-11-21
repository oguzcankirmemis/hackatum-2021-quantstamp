//SPDX-License-Identifier: Unlicense
pragma solidity 0.7.0;

import "./interfaces/IBank.sol";
import "./interfaces/IPriceOracle.sol";
import {DSMath} from "./libraries/Math.sol";
import "@openzeppelin/contracts@v3.4.0/token/ERC20/IERC20.sol";

contract Bank is IBank {
    struct Customer {
        IBank.Account ethAccount;
        IBank.Account hakAccount;
        uint256 borrowed;
        uint256 borrowInterest;
        uint256 borrowBlock;
    }

    struct SimpleBank {
        address owner;
        uint256 ethAmount;
        uint256 hakAmount;
    }

    IPriceOracle private priceOracle;
    address private hakToken;
    address private ethToken = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    IERC20 private hak;
    IERC20 private eth;

    SimpleBank private bank;

    mapping(address => Customer) private customerAccounts;

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
                hak.transferFrom(msg.sender, address(this), amount);
                uint256 hakInterest = DSMath.mul(
                    DSMath.sub(block.number, customer.hakAccount.lastInterestBlock), 3);
                customer.hakAccount.lastInterestBlock = block.number;
                uint256 hakInterestVal = DSMath.mul(customer.hakAccount.deposit, hakInterest) / 10000;
                customer.hakAccount.interest = DSMath.add(customer.hakAccount.interest, hakInterestVal);
                customer.hakAccount.deposit = DSMath.add(customer.hakAccount.deposit, amount);
                bank.hakAmount = DSMath.add(bank.hakAmount, amount);
                emit Deposit(msg.sender, token, amount);
                return true;
            } else if(token == ethToken) {
                require(amount == msg.value, "amount not equal to sent");
                uint256 ethInterest = DSMath.mul(
                    DSMath.sub(block.number, customer.ethAccount.lastInterestBlock), 3);
                customer.ethAccount.lastInterestBlock = block.number;
                uint256 ethInterestVal = DSMath.mul(customer.ethAccount.deposit, ethInterest) / 10000;
                customer.ethAccount.interest = DSMath.add(customer.ethAccount.interest, ethInterestVal);
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
                if (amount == 0) {
                    amount = customer.hakAccount.deposit;
                }
                uint256 hakInterest = DSMath.mul(
                    DSMath.sub(block.number, customer.hakAccount.lastInterestBlock), 3);
                customer.hakAccount.lastInterestBlock = block.number;
                uint256 hakInterestVal = DSMath.mul(customer.hakAccount.deposit, hakInterest) / 10000;
                uint256 toSend = DSMath.add(DSMath.add(amount, hakInterestVal), customer.hakAccount.interest);
                customer.hakAccount.interest = 0;
                require(amount <= customer.hakAccount.deposit, "amount exceeds balance");
                require(toSend <= bank.hakAmount, "hak bankrupt");
                bank.hakAmount = DSMath.sub(bank.hakAmount, toSend);
                customer.hakAccount.deposit = DSMath.sub(customer.hakAccount.deposit, amount);
                hak.transfer(payable(msg.sender), toSend);
                emit Withdraw(msg.sender, token, toSend);
                return toSend;
            } else if (token == ethToken) {
                require(customer.ethAccount.deposit != 0, "no balance");
                if (amount == 0) {
                    amount = customer.ethAccount.deposit;
                }
                uint256 ethInterest = DSMath.mul(
                    DSMath.sub(block.number, customer.ethAccount.lastInterestBlock), 3);
                customer.ethAccount.lastInterestBlock = block.number;
                uint256 ethInterestVal = DSMath.mul(customer.ethAccount.deposit, ethInterest) / 10000;
                uint256 toSend = DSMath.add(DSMath.add(amount, ethInterestVal), customer.ethAccount.interest);
                customer.ethAccount.interest = 0;
                require(amount <= customer.ethAccount.deposit, "amount exceeds balance");
                require(toSend <= bank.ethAmount, "eth bankrupt");
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
            Customer storage customer = customerAccounts[msg.sender];
            require(token == ethToken, "token not supported");
            require(customer.hakAccount.deposit > 0, "no collateral deposited");
            require(amount <= bank.ethAmount, "eth bank bankrupt");
            address payable account = msg.sender;
            if (customer.borrowed == 0) {
                customer.borrowBlock = block.number;
            }
            uint256 ethHakPrice = priceOracle.getVirtualPrice(hakToken);
            uint256 cRatio = _getCollateralRatio(customer, amount);
            require(cRatio >= 15000, "borrow would exceed collateral ratio");
            uint256 borrowInterest = DSMath.mul(customer.borrowed,
                DSMath.mul(DSMath.sub(block.number, customer.borrowBlock), 5)) / 10000;
            customer.borrowInterest = DSMath.add(customer.borrowInterest, borrowInterest);
            customer.borrowBlock = block.number;
            customer.borrowed = DSMath.add(customer.borrowed, amount);
            if (amount == 0) {
                uint256 d_i_curr = DSMath.mul(
                    DSMath.sub(block.number, customer.hakAccount.lastInterestBlock), 3);
                customer.hakAccount.lastInterestBlock = block.number;
                uint256 d_i_curr_val = DSMath.mul(customer.hakAccount.deposit, d_i_curr) / 10000;
                uint256 d = customer.hakAccount.deposit;
                uint256 d_i = DSMath.add(customer.hakAccount.interest, d_i_curr_val);
                uint256 totalDeposit = DSMath.mul(DSMath.add(d, d_i), ethHakPrice) / 10 ** 18;
                customer.hakAccount.interest = d_i;
                uint256 b_i = DSMath.mul(
                    DSMath.sub(block.number, customer.borrowBlock), 5);
                uint256 maxBorrow = DSMath.mul(DSMath.sub((DSMath.mul(
                    totalDeposit, 10000) / 15000), customer.borrowInterest) / DSMath.add(100, b_i), 100);
                uint256 toSend = DSMath.sub(maxBorrow, customer.borrowed);
                if (toSend > bank.ethAmount) {
                    toSend = bank.ethAmount;
                }
                bank.ethAmount = DSMath.sub(bank.ethAmount, toSend);
                customer.borrowed = maxBorrow;
                account.transfer(toSend);
                emit Borrow(account, ethToken, toSend, 15000);
                return 15000;
            } else {
                account.transfer(amount);
                emit Borrow(account, ethToken, amount, cRatio);
                return cRatio;
            }
        }

    function repay(address token, uint256 amount)
        payable
        external
        override
        returns (uint256) {
            require(token == ethToken, "token not supported");
            require(amount <= msg.value, "msg.value < amount to repay");
            uint256 toSendBack = DSMath.sub(msg.value, amount);
            Customer storage customer = customerAccounts[msg.sender];
            address payable account = msg.sender;
            bank.ethAmount = DSMath.add(bank.ethAmount, amount);
            require(DSMath.add(customer.borrowed, customer.borrowInterest) > 0, "nothing to repay");
            uint256 borrowInterest = DSMath.mul(
                DSMath.sub(block.number, customer.borrowBlock), 5);
            uint256 borrowInterestVal = DSMath.mul(borrowInterest, customer.borrowed) / 10000;
            customer.borrowInterest = DSMath.add(customer.borrowInterest, borrowInterestVal);
            if (amount == 0) {
                amount = DSMath.add(customer.borrowed, customer.borrowInterest);
                if (amount > msg.value) {
                    amount = msg.value;
                }
                toSendBack = DSMath.sub(msg.value, amount);
            }
            if (amount >= customer.borrowInterest) {
                amount = DSMath.sub(amount, customer.borrowInterest);
                customer.borrowInterest = 0;
            } else {
                customer.borrowInterest = DSMath.sub(customer.borrowInterest, amount);
                amount = 0;
            }
            if (amount >= customer.borrowed) {
                amount = DSMath.sub(amount, customer.borrowed);
                customer.borrowed = 0;
            } else {
                customer.borrowed = DSMath.sub(customer.borrowed, amount);
                amount = 0;
            }
            toSendBack = DSMath.add(toSendBack, amount);
            account.transfer(toSendBack);
            emit IBank.Repay(account, token, customer.borrowed);
            return customer.borrowed;
        }

    function liquidate(address token, address account)
        payable
        external
        override
        returns (bool) {
            require(token == hakToken, "token not supported");
            require(account != msg.sender, "cannot liquidate own position");
            require(getCollateralRatio(token, account) < 15000, "healty position");
            address payable payer = msg.sender;
            Customer storage customer = customerAccounts[account];
            uint256 borrowInterest = DSMath.mul(
                DSMath.sub(block.number, customer.borrowBlock), 5);
            uint256 debt = DSMath.add(DSMath.add(customer.borrowed, customer.borrowInterest),
                DSMath.mul(borrowInterest, customer.borrowed) / 10000);
            require(debt <= msg.value, "insufficient ETH sent by liquidator");
            uint256 sendBack = DSMath.sub(msg.value, debt);
            bank.ethAmount = DSMath.add(bank.ethAmount, debt);
            payer.transfer(sendBack);
            customer.borrowed = 0;
            uint256 amountCollateral = DSMath.add(customer.hakAccount.deposit, customer.hakAccount.interest);
            uint256 hakInterest = DSMath.mul(
                DSMath.sub(block.number, customer.hakAccount.lastInterestBlock), 3);
            uint256 hakInterestVal = DSMath.mul(customer.hakAccount.deposit, hakInterest) / 10000;
            amountCollateral = DSMath.add(amountCollateral, hakInterestVal);
            customerAccounts[payer].hakAccount.deposit = DSMath.add(
                customerAccounts[payer].hakAccount.deposit, amountCollateral);
            customer.hakAccount.deposit = 0;
            customer.hakAccount.interest = 0;
            customer.hakAccount.lastInterestBlock = block.number;
            hak.transfer(payer, amountCollateral);
            emit IBank.Liquidate(
                payer, account, token, amountCollateral, sendBack);
            return true;
        }

    function getCollateralRatio(address token, address account)
        view
        public
        override
        returns (uint256) {
            Customer memory customer = customerAccounts[account];
            if (token != hakToken) {
                revert("token not supported");
            }
            uint256 ethHakPrice = priceOracle.getVirtualPrice(hakToken);
            if (customer.hakAccount.deposit == 0) {
                return 0;
            }
            if (customer.borrowed == 0) {
                return type(uint256).max;
            }
            uint256 borrowInterest = DSMath.mul(
                DSMath.sub(block.number, customer.borrowBlock), 5);
            uint256 debt = DSMath.add(DSMath.add(customer.borrowed, customer.borrowInterest),
                DSMath.mul(borrowInterest, customer.borrowed) / 10000);
            uint256 depositInterest = DSMath.mul(
                DSMath.sub(block.number, customer.hakAccount.lastInterestBlock), 3);
            uint256 depositInterestVal = DSMath.mul(customer.hakAccount.deposit, depositInterest) / 10000;
            uint256 depositVal = DSMath.mul(DSMath.add(customer.hakAccount.deposit,
                DSMath.add(customer.hakAccount.interest, depositInterestVal)), ethHakPrice);
            return (depositVal / debt) / 10**14;
        }

    function getBalance(address token)
        view
        public
        override
        returns (uint256) {
            Customer memory customer = customerAccounts[msg.sender];
            if (token == hakToken) {
                uint256 hakInterest = DSMath.mul(
                    DSMath.sub(block.number, customer.hakAccount.lastInterestBlock), 3);
                customer.hakAccount.lastInterestBlock = block.number;
                uint256 hakInterestVal = DSMath.mul(customer.hakAccount.deposit, hakInterest) / 10000;
                customer.hakAccount.interest = DSMath.add(customer.hakAccount.interest, hakInterestVal);
                return DSMath.add(customer.hakAccount.deposit,
                    customer.hakAccount.interest);
            } else if (token == ethToken) {
                uint256 ethInterest = DSMath.mul(
                    DSMath.sub(block.number, customer.ethAccount.lastInterestBlock), 3);
                customer.ethAccount.lastInterestBlock = block.number;
                uint256 ethInterestVal = DSMath.mul(customer.ethAccount.deposit, ethInterest) / 10000;
                customer.ethAccount.interest = DSMath.add(customer.ethAccount.interest, ethInterestVal);
                uint256 borrowInterest = DSMath.mul(
                    DSMath.sub(block.number, customer.borrowBlock), 5);
                uint256 debt = DSMath.add(DSMath.add(customer.borrowed, customer.borrowInterest),
                    DSMath.mul(borrowInterest, customer.borrowed) / 10000);
                return DSMath.sub(DSMath.add(customer.ethAccount.deposit,
                    customer.ethAccount.interest), debt);
            } else {
                revert("token not supported");
            }
        }

    function _getCollateralRatio(Customer memory customer, uint256 extraDebt)
        view
        private
        returns (uint256) {
            if (customer.hakAccount.deposit == 0) {
                return 0;
            }
            if (DSMath.add(customer.borrowed, extraDebt) == 0) {
                return type(uint256).max;
            }
            uint256 ethHakPrice = priceOracle.getVirtualPrice(hakToken);
            uint256 borrowInterest = DSMath.mul(
                DSMath.sub(block.number, customer.borrowBlock), 5);
            uint256 debt = DSMath.add(DSMath.add(customer.borrowed, customer.borrowInterest),
                DSMath.mul(borrowInterest, customer.borrowed) / 10000);
            debt = DSMath.add(debt, extraDebt);
            uint256 depositInterest = DSMath.mul(
                DSMath.sub(block.number, customer.hakAccount.lastInterestBlock), 3);
            uint256 depositInterestVal = DSMath.mul(customer.hakAccount.deposit, depositInterest) / 10000;
            uint256 depositVal = DSMath.mul(DSMath.add(customer.hakAccount.deposit,
                DSMath.add(customer.hakAccount.interest, depositInterestVal)), ethHakPrice);
            return (depositVal / debt) / 10**14;
    }
}
