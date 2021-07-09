// This contract is under development and has not yet been deployed on mainnet

pragma solidity ^0.8.0;

import './interfaces/IERC20.sol';

import './utils/Ownable.sol';

/*
    Using this contract, people can transfer their coins bypassing
    any limits of the Energy 8 token. But in order not to violate the
    tokenomics, there is a small condition: you can transfer coins
    using this contract only once every 24 hours.

    When is it needed:
    - a person wants to quickly transfer all their coins to another wallet
    - a person wants to transfer their coins to one of the exchanges

    We trust our holders and are confident that they will only use this contract for good purposes.
*/
contract NoLimitTransfer is Ownable {
    mapping (address => uint) public lastTransferTime;
    mapping (address => bool) private _senderBlacklist;
    mapping (address => bool) private _recipientBlacklist;
    uint private timeLimit = 1 days;

    IERC20 private _token;

    constructor(IERC20 token) {
        _token = token;
    }

    function transfer(address to, uint amount) external {
        require(!_senderBlacklist[msg.sender], "You are blacklisted ;_;");
        require(!_recipientBlacklist[to], "Recipient is blacklisted ;_;");
        require(block.timestamp >= lastTransferTime[msg.sender] + timeLimit, "You cannot transfer tokens yet");

        _token.transferFrom(msg.sender, to, amount);

        lastTransferTime[msg.sender] = block.timestamp;
    }

    function resetTransferTime(address account) external onlyOwner {
        lastTransferTime[account] = 0;
    }

    function setTimeLimit(uint _timeLimit) external onlyOwner {
        timeLimit = _timeLimit;
    }

    function setSenderBlacklist(address account, bool value) external onlyOwner {
        _senderBlacklist[account] = value;
    }

    function setRecipientBlacklist(address account, bool value) external onlyOwner {
        _recipientBlacklist[account] = value;
    }
}
