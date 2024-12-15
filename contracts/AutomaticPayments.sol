// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AutomaticPayments is ERC2771Context, Ownable {
    using ECDSA for bytes32;

    struct RecurringPayment {
        address to;
        uint256 amount;
        uint256 frequency;
        uint256 validUntil;
        bool isActive;
        address tokenAddress;
    }

    mapping(address => mapping(address => RecurringPayment)) public payments;
    mapping(address => mapping(address => uint256)) public lastPaymentTime;

    event PaymentAuthorized(
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 frequency,
        uint256 validUntil,
        address indexed tokenAddress
    );

    event PaymentExecuted(
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 timestamp,
        address indexed tokenAddress
    );

    event PaymentCancelled(address indexed from, address indexed to);

    constructor(
        address trustedForwarder
    ) ERC2771Context(trustedForwarder) Ownable(msg.sender) {}

    function authorizePayment(
        address to,
        uint256 amount,
        uint256 frequency,
        uint256 validUntil,
        address tokenAddress
    ) public {
        require(to != address(0), "Invalid recipient");
        require(tokenAddress != address(0), "Invalid token address");
        require(amount > 0, "Amount must be greater than 0");
        require(frequency > 0, "Frequency must be greater than 0");
        require(validUntil > block.timestamp, "Invalid expiration time");

        payments[_msgSender()][to] = RecurringPayment({
            to: to,
            amount: amount,
            frequency: frequency,
            validUntil: validUntil,
            isActive: true,
            tokenAddress: tokenAddress
        });

        emit PaymentAuthorized(
            _msgSender(),
            to,
            amount,
            frequency,
            validUntil,
            tokenAddress
        );
    }

    function executePayment(address from, address to) public {
        RecurringPayment storage payment = payments[from][to];
        require(payment.isActive, "Payment not authorized");
        require(block.timestamp <= payment.validUntil, "Authorization expired");

        uint256 lastPayment = lastPaymentTime[from][to];
        require(
            lastPayment == 0 ||
                block.timestamp >= lastPayment + payment.frequency,
            "Payment too soon"
        );

        IERC20 token = IERC20(payment.tokenAddress);
        require(
            token.balanceOf(from) >= payment.amount,
            "Insufficient token balance"
        );

        lastPaymentTime[from][to] = block.timestamp;

        require(
            token.transferFrom(from, payment.to, payment.amount),
            "Transfer failed"
        );

        emit PaymentExecuted(
            from,
            to,
            payment.amount,
            block.timestamp,
            payment.tokenAddress
        );
    }

    function cancelPayment(address to) public {
        require(payments[_msgSender()][to].isActive, "No active payment found");
        payments[_msgSender()][to].isActive = false;
        emit PaymentCancelled(_msgSender(), to);
    }

    function getPaymentInfo(
        address from,
        address to
    ) public view returns (RecurringPayment memory) {
        return payments[from][to];
    }

    function getLastPaymentTime(
        address from,
        address to
    ) public view returns (uint256) {
        return lastPaymentTime[from][to];
    }

    function canExecutePayment(
        address from,
        address to
    ) public view returns (bool) {
        RecurringPayment storage payment = payments[from][to];
        if (!payment.isActive || block.timestamp > payment.validUntil) {
            return false;
        }

        uint256 lastPayment = lastPaymentTime[from][to];
        return
            lastPayment == 0 ||
            block.timestamp >= lastPayment + payment.frequency;
    }

    function _msgSender()
        internal
        view
        override(Context, ERC2771Context)
        returns (address)
    {
        return ERC2771Context._msgSender();
    }

    function _msgData()
        internal
        view
        override(Context, ERC2771Context)
        returns (bytes calldata)
    {
        return ERC2771Context._msgData();
    }

    function _contextSuffixLength()
        internal
        view
        override(Context, ERC2771Context)
        returns (uint256)
    {
        return ERC2771Context._contextSuffixLength();
    }
}
