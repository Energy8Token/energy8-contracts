pragma solidity ^0.8.0;

interface IERC20 {
  function transfer(address recipient, uint256 amount) external returns (bool);
}

contract Airdrop {
    address public owner;
    IERC20 private token;

    constructor(IERC20 _token) {
        owner = msg.sender;
        token = _token;
    }
    
    function airdrop(address[] calldata recipients, uint256[] calldata amounts) external {
        require(owner == msg.sender, "-_-");

        uint recipientsLength = recipients.length;
        
        for (uint i = 0; i < recipientsLength; i++) {
            token.transfer(recipients[i], amounts[i] * 10**9);
        }
    }
}
