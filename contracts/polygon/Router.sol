// This contract is under development and has not yet been deployed on mainnet

pragma solidity ^0.8.0;

import './interfaces/IERC20.sol';

import './utils/Ownable.sol';

interface IRouter {
  event Deposit(uint32 serverId, string username, address indexed sender, uint value);
  event Withdraw(uint32 serverId, string username, address indexed recipient, uint value);
}

contract Router is IRouter, Ownable {
  struct Game {
    string name; // readable game name for dapp
    string icon; // link to the game icon for dapp
    bool isActive;
  }

  struct Server {
    string name; // readable server name for dapp
    string icon; // link to the server icon for dapp. If not, then you need to use the game icon 
    address adminAddress;
    uint8 gameId;
    uint32 depositFeeAdmin;
    uint32 depositBurn;
    uint32 depositFee;
    uint32 withdrawFeeAdmin;
    uint32 withdrawBurn;
    uint32 withdrawFee;
    bool isActive;
  }
  
  Game[] public games;
  Server[] public servers;

  address private constant DEAD = 0x000000000000000000000000000000000000dEaD;
  IERC20 private immutable _token;

  modifier onlyOwnerOrServerAdmin(uint32 serverId) {
    require(_owner == msg.sender || servers[serverId].adminAddress == msg.sender, "-_-");
    _;
  }
  
  constructor(IERC20 token) {
    _token = token;
  }
  
  function deposit(uint32 serverId, string calldata nickname, uint amount) external {
    require(amount > 0, "Amount must be greater than 0");

    Server storage server = servers[serverId];

    require(games[server.gameId].isActive, "The game of this server not found or inactive");
    require(server.isActive, "The server not found or inactive");
    
    uint adminFeeAmount = _getPercentage(amount, server.depositFeeAdmin);
    uint burnAmount = _getPercentage(amount, server.depositBurn);
    uint feeAmount = _getPercentage(amount, server.depositFee);
    
    uint depositAmount = amount - adminFeeAmount - burnAmount - feeAmount;

    _token.transferFrom(msg.sender, address(this), amount);

    if (burnAmount > 0) {
      _token.transfer(DEAD, burnAmount);
    }

    if (adminFeeAmount > 0) {
      _token.transfer(server.adminAddress, adminFeeAmount);
    }

    emit Deposit(serverId, nickname, msg.sender, depositAmount);
  }
  
  /*
    At the moment, the withdrawal is made on behalf of the owner,
    because it is necessary to ensure that the withdrawal is made
    directly by the owner of the game account, for this,
    certain checks are made on the centralized server
    
    In future versions of the router this will be rewritten
    and there will be no centralized server 
  */
  function withdraw(uint32 serverId, address recipient, string calldata nickname, uint amount) external onlyOwner {
    require(amount > 0, "Amount must be greater than 0");

    Server storage server = servers[serverId];
    
    uint adminFeeAmount = _getPercentage(amount, server.withdrawFeeAdmin);
    uint burnAmount = _getPercentage(amount, server.withdrawBurn);
    uint feeAmount = _getPercentage(amount, server.withdrawFee);
    
    uint withdrawAmount = amount - adminFeeAmount - burnAmount - feeAmount;
    
    _token.transfer(recipient, withdrawAmount);
    
    if (burnAmount > 0) {
      _token.transfer(DEAD, burnAmount);
    }
    
    if (adminFeeAmount > 0) {
      _token.transfer(server.adminAddress, adminFeeAmount);
    }
      
    emit Withdraw(serverId, nickname, recipient, amount);
  }

  function addGame(string calldata name, string calldata icon, bool isActive) external onlyOwner {
    games.push(
      Game(name, icon, isActive)
    );
  }
  
  function addServer(uint8 gameId, string calldata name, string calldata icon, address adminAddress, bool isActive) external onlyOwner {
    require(games[gameId].isActive, "The game with this gameId does not exist or inactive");

    servers.push(
      Server({
        name: name,
        icon: icon,
        adminAddress: adminAddress,
        gameId: gameId,
        depositFeeAdmin: 0,
        depositBurn: 0,
        depositFee: 0,
        withdrawFeeAdmin: 0,
        withdrawBurn: 0,
        withdrawFee: 0,
        isActive: isActive
      })
    );
  }
  
  function setServerDepositFees(
    uint32 serverId,
    uint32 depositFeeAdmin,
    uint32 depositBurn,
    uint32 depositFee
  ) external onlyOwnerOrServerAdmin(serverId) {
    require(
      depositFeeAdmin <= 10000 &&
      depositBurn <= 10000 &&
      depositFee <= 10000
    );

    Server storage server = servers[serverId];
    
    server.depositFeeAdmin = depositFeeAdmin;
    server.depositBurn = depositBurn;
    server.depositFee = depositFee;
  }
  
  function setServerWithdrawFees(
    uint32 serverId,
    uint32 withdrawFeeAdmin,
    uint32 withdrawBurn,
    uint32 withdrawFee
  ) external onlyOwnerOrServerAdmin(serverId) {
    require(
      withdrawFeeAdmin <= 10000 &&
      withdrawBurn <= 10000 &&
      withdrawFee <= 10000
    );

    Server storage server = servers[serverId];
    
    server.withdrawFeeAdmin = withdrawFeeAdmin;
    server.withdrawBurn = withdrawBurn;
    server.withdrawFee = withdrawFee;
  }
  
  function setServerAdmin(uint32 serverId, address adminAddress) external onlyOwnerOrServerAdmin(serverId) {
    servers[serverId].adminAddress = adminAddress;
  }
  
  function setServerName(uint32 serverId, string calldata name) external onlyOwnerOrServerAdmin(serverId) { 
    servers[serverId].name = name;
  }
  
  function setServerIcon(uint32 serverId, string calldata icon) external onlyOwnerOrServerAdmin(serverId) {
    servers[serverId].icon = icon;
  }
  
  function setServerActive(uint32 serverId, bool value) external onlyOwnerOrServerAdmin(serverId) {
    servers[serverId].isActive = value;
  }

  function setGameName(uint32 gameId, string calldata name) external onlyOwner { 
    games[gameId].name = name;
  }
  
  function setGameIcon(uint32 gameId, string calldata icon) external onlyOwner {
    games[gameId].icon = icon;
  }

  function setGameActive(uint32 gameId, bool value) external onlyOwner {
    games[gameId].isActive = value;
  }
  
  function grabStuckTokens(IERC20 token, address wallet, uint amount) external onlyOwner {
    token.transfer(wallet, amount);
  }
  
  function serversNumber() external view returns (uint) {
    return servers.length;
  }

  function gamesNumber() external view returns (uint) {
      return games.length;
  }
  
  function _getPercentage(uint number, uint32 percent) internal pure returns (uint) {
    return (number * percent) / 10000;
  }
}
