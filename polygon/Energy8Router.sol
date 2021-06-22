pragma solidity ^0.8.0;

interface IERC20 {
  function transfer(address recipient, uint256 amount) external returns (bool);
  function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

interface IEnergy8Router {
  event Deposit(uint32 serverId, string username, address indexed sender, uint256 value);
  event Withdraw(uint32 serverId, string username, address indexed recipient, uint256 value);
}

abstract contract Ownable {
  address private _owner;

  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

  constructor () {
    _owner = msg.sender;
    emit OwnershipTransferred(address(0), msg.sender);
  }

  function owner() public view returns (address) {
    return _owner;
  }

  modifier onlyOwner() {
    require(_owner == msg.sender, "-_-");
    _;
  }

  function transferOwnership(address newOwner) public onlyOwner {
    emit OwnershipTransferred(_owner, newOwner);
    _owner = newOwner;
  }
}

contract Energy8Router is IEnergy8Router, Ownable {
  struct Server {
    string name;
    string icon;
    address adminAddress;
    uint8 depositFeeAdmin;
    uint8 depositBurn;
    uint8 depositFee;
    uint8 withdrawFeeAdmin;
    uint8 withdrawBurn;
    uint8 withdrawFee;
    bool isActive;
  }
  
  mapping (uint32 => Server) public servers;
  uint32 public serversNumber = 0;
  address public deadAddress = 0x000000000000000000000000000000000000dEaD;
  IERC20 private token;
  
  constructor(IERC20 _token) {
    token = _token;
  }
  
  function deposit(uint32 serverId, string calldata nickname, uint256 amount) external {
    require(amount > 0, "Amount must be greater than 0");

    Server storage server = _getServer(serverId);
    
    uint256 adminFeeAmount = _getPercentage(amount, server.depositFeeAdmin);
    uint256 burnAmount = _getPercentage(amount, server.depositBurn);
    uint256 feeAmount = _getPercentage(amount, server.depositFee);
    
    uint256 depositAmount = amount - adminFeeAmount - burnAmount - feeAmount;
    
    token.transferFrom(msg.sender, address(this), amount);

    if (adminFeeAmount > 0) {
        token.transfer(server.adminAddress, adminFeeAmount);
    }
    
    if (burnAmount > 0) {
        token.transfer(deadAddress, burnAmount);
    }

    emit Deposit(serverId, nickname, msg.sender, depositAmount);
  }
  
  function withdraw(uint32 serverId, address recipient, string calldata nickname, uint256 amount) external onlyOwner {
    require(amount > 0, "Amount must be greater than 0");

    Server storage server = _getServer(serverId);
    
    uint256 adminFeeAmount = _getPercentage(amount, server.withdrawFeeAdmin);
    uint256 burnAmount = _getPercentage(amount, server.withdrawBurn);
    uint256 feeAmount = _getPercentage(amount, server.withdrawFee);
    
    uint256 withdrawAmount = amount - adminFeeAmount - burnAmount - feeAmount;
    
    token.transfer(recipient, withdrawAmount);
    
    if (burnAmount > 0) {
        token.transfer(deadAddress, burnAmount);
    }
    
    if (adminFeeAmount > 0) {
        token.transfer(server.adminAddress, adminFeeAmount);
    }
      
    emit Withdraw(serverId, nickname, recipient, amount);
  }
  
  function addServer(string calldata name, string calldata icon, address adminAddress) external onlyOwner returns (uint32) {
    uint32 _serversNumber = serversNumber;

    servers[_serversNumber] = Server(name, icon, adminAddress, 0, 0, 0, 0, 0, 0, true);

    serversNumber += 1;
    
    return _serversNumber;
  }
  
  function setServerDepositFees(uint32 serverId, uint8 depositFeeAdmin, uint8 depositBurn, uint8 depositFee) external onlyOwner {
    require(depositFeeAdmin >= 0 && depositFeeAdmin <= 10000);
    require(depositBurn >= 0 && depositBurn <= 10000);
    require(depositFee >= 0 && depositFee <= 10000);

    Server storage server = servers[serverId];
    
    server.depositFeeAdmin = depositFeeAdmin;
    server.depositBurn = depositBurn;
    server.depositFee = depositFee;
  }
  
  function setServerWithdrawFees(uint32 serverId, uint8 withdrawFeeAdmin, uint8 withdrawBurn, uint8 withdrawFee) external onlyOwner {
    require(withdrawFeeAdmin >= 0 && withdrawFeeAdmin <= 10000);
    require(withdrawBurn >= 0 && withdrawBurn <= 10000);
    require(withdrawFee >= 0 && withdrawFee <= 10000);

    Server storage server = servers[serverId];
    
    server.withdrawFeeAdmin = withdrawFeeAdmin;
    server.withdrawBurn = withdrawBurn;
    server.withdrawFee = withdrawFee;
  }
  
  function setServerAdmin(uint32 serverId, address adminAddress) external onlyOwner {
    servers[serverId].adminAddress = adminAddress;
  }
  
  function setServerName(uint32 serverId, string calldata name) external onlyOwner { 
    servers[serverId].name = name;
  }
  
  function setServerIcon(uint32 serverId, string calldata icon) external onlyOwner {
    servers[serverId].icon = icon;
  }
  
  function setActiveStatus(uint32 serverId, bool value) external onlyOwner {
    servers[serverId].isActive = value;
  }
  
  function grabTokens(IERC20 _token, address wallet, uint256 amount) external onlyOwner {
    _token.transfer(wallet, amount);
  }

  function _getServer(uint32 serverId) internal view returns (Server storage) {
    Server storage server = servers[serverId];
      
    require(server.isActive, "Server not found or inactive");
      
    return server;
  }
  
  function _getPercentage(uint256 number, uint8 percent) internal pure returns (uint256) {
    return (number * percent) / 10000;
  }
}
