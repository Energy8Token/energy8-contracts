// This contract is under development and has not yet been deployed on mainnet

pragma solidity ^0.8.0;

import './interfaces/IERC20.sol';
import './interfaces/IPancakePair.sol';

import './utils/Ownable.sol';
import './utils/Lockable.sol';

contract YieldFarmingWithoutMinting is Ownable, Lockable {
  struct Farm {
    IERC20 token;
    IPancakePair lpToken;
    string token0Symbol;
    string token1Symbol;
    uint id;
    uint startsAt;
    uint lastRewardedBlock;
    uint lpLockTime;
    uint numberOfFarmers;
    uint lpTotalAmount;
    bool isActive;
  }

  struct Farmer {
    uint balance;
    uint startBlock;
    uint startTime;
  }

  Farm[] public farms;
  mapping(uint => mapping (address => Farmer)) private _farmers;
  mapping(address => bool) private _pools;

  uint public creationFee;

  constructor(uint _creationFee) {
    creationFee = _creationFee;
  }

  receive() external payable {}

  function createFarm(
    IERC20 token,
    IPancakePair lpToken,
    uint startsAt,
    uint lastRewardedBlock,
    uint lpLockTime
  ) external payable {
    require(!_pools[address(lpToken)], "This pool is already exist");

    if (msg.sender != _owner) {
      require(msg.value >= creationFee);
    }

    address token0 = lpToken.token0();
    address token1 = lpToken.token1();

    require(token0 == address(token) || token1 == address(token));

    _pools[address(lpToken)] = true;

    farms.push(
      Farm({
        token: token,
        lpToken: lpToken,
        token0Symbol: IERC20(token0).name(),
        token1Symbol: IERC20(token1).name(),
        id: farms.length,
        startsAt: startsAt,
        lastRewardedBlock: lastRewardedBlock,
        lpLockTime: lpLockTime,
        numberOfFarmers: 0,
        lpTotalAmount: 0,
        isActive: true
      })
    );
  }
  
  function stake(uint farmId, uint amount) external withLock {
    require(amount > 0, "Amount must be greater than zero");

    Farm storage farm = farms[farmId];
    Farmer storage farmer = _farmers[farmId][msg.sender];

    require(farm.isActive, "This farm is inactive or not exist");
    require(block.timestamp > farm.startsAt, "Yield farming has not started yet for this farm");
    require(block.number < farm.lastRewardedBlock, "Yield farming is currently closed for this farm");
    
    farm.lpToken.transferFrom(msg.sender, address(this), amount);
    farm.lpTotalAmount += amount;
    farmer.balance += amount;

    if (farmer.startBlock == 0) {
      farm.numberOfFarmers += 1;
      farmer.startBlock = block.number;
      farmer.startTime = block.timestamp;
    }
  }

  /*
    withdraw only reward
  */
  function harvest(uint farmId) external withLock {
    _withdrawHarvest(farms[farmId], _farmers[farmId][msg.sender]);
  }

  /*
    withdraw both lp tokens and reward
  */
  function withdraw(uint farmId) external withLock {
    Farm storage farm = farms[farmId];
    Farmer storage farmer = _farmers[farmId][msg.sender];
    
    _withdrawHarvest(farm, farmer);
    _withdrawLP(farm, farmer);
  }

  /*
    withdraw only lp tokens
  */
  function emergencyWithdraw(uint farmId) external withLock {
    _withdrawLP(farms[farmId], _farmers[farmId][msg.sender]);
  }

  function _withdrawLP(Farm storage farm, Farmer storage farmer) internal {
    uint amount = farmer.balance;

    require(amount > 0, "Balance must be greater than zero");

    farm.lpToken.transfer(msg.sender, amount);
    farm.numberOfFarmers -= 1;
    farm.lpTotalAmount -= amount;

    farmer.startBlock = 0;
    farmer.startTime = 0;
    farmer.balance = 0;
  }

  function _withdrawHarvest(Farm memory farm, Farmer memory farmer) internal {
    require(farmer.startBlock != 0, "You are not a farmer");
    require(block.timestamp >= farmer.startTime + farm.lpLockTime, "Too early for withdraw");

    uint harvestAmount = _calculateYield(farm, farmer);

    farm.token.transfer(msg.sender, harvestAmount);
  }
  
  function yield(uint farmId) external view returns (uint) {
    return _calculateYield(farms[farmId], _farmers[farmId][msg.sender]);
  }

  function _calculateYield(Farm memory farm, Farmer memory farmer) internal view returns (uint) {
    uint lpTotalAmount = farm.lpTotalAmount;
    uint startBlock = farmer.startBlock;

    if (lpTotalAmount == 0 || startBlock == 0) {
      return 0;
    }
    
    uint rewardedBlocks = block.number - startBlock;
    uint tokensPerFarmer = (rewardedBlocks * farm.token.balanceOf(address(this))) / farm.lastRewardedBlock;
    uint balanceRate = (farmer.balance * 10**9) / lpTotalAmount;

    return (tokensPerFarmer * balanceRate) / 10**9;
  }
  
  function updateFarm(
    uint farmId,
    uint startsAt,
    uint lastRewardedBlock,
    uint lpLockTime
  ) external onlyOwner {
    Farm storage farm = farms[farmId];

    farm.startsAt = startsAt;
    farm.lastRewardedBlock = lastRewardedBlock;
    farm.lpLockTime = lpLockTime;
  }

  function setActive(uint farmId, bool value) external onlyOwner {
    farms[farmId].isActive = value;
  }
  
  function setCreationFee(uint _creationFee) external onlyOwner {
    creationFee = _creationFee;
  }

  function withdrawFees() external onlyOwner {
    payable(msg.sender).transfer(address(this).balance);
  }
}
