pragma solidity ^0.8.0;

interface IERC20 {
  function transfer(address recipient, uint256 amount) external returns (bool);
}

contract Migrator {
    address public owner;
    address public admin;
    mapping (address => bool) public migrated;
    
    IERC20 private token;

    constructor(IERC20 _token) {
        owner = msg.sender;
        admin = msg.sender;
        token = _token;
    }
    
    function migrate(address from, address payable to, uint amount) external {
        require(admin == msg.sender || owner == msg.sender, "-_-");
        require(!migrated[from], "You have already migrated");
        
        migrated[from] = true;
        
        token.transfer(to, amount);
        to.transfer(3000000 gwei); // 0.003 MATIC
    }
    
    function setAdmin(address account) external {
        require(owner == msg.sender, "-_-");

        admin = account;
    }

    function grabStuckTokens(IERC20 _token, uint amount) external {
        require(owner == msg.sender, "-_-");

        _token.transfer(msg.sender, amount);
    }
}
