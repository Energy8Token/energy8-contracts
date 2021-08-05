// This contract is under development and has not yet been deployed on mainnet

pragma solidity ^0.8.0;

import './interfaces/IERC20.sol';
import './interfaces/IPancakePair.sol';
import './interfaces/IPancakeRouter.sol';

import './utils/Ownable.sol';
import './utils/Lockable.sol';

contract YieldFarmingWithoutMinting is Ownable, Lockable {
  struct Farm {
    address creator;
    IERC20 token;
    IPancakePair lpToken;
    uint id;
    uint startsAt;
    uint lastRewardedBlock;
    uint lpLockTime;
    uint numberOfFarmers;
    uint lpTotalAmount;
    uint farmersLimit;
    uint maxStakePerFarmer;
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

  event FarmCreated(uint farmId);

  constructor(uint _creationFee) {
    creationFee = _creationFee;
  }

  receive() external payable {}

  function createFarm(
    IERC20 token,
    IPancakePair lpToken,
    uint startsAt,
    uint durationInBlocks,
    uint lpLockTime,
    uint farmersLimit,
    uint maxStakePerFarmer
  ) external payable {
    if (msg.sender != _owner) {
      require(msg.value >= creationFee, "You need to pay fee for creating own yield farm");
    }

    require(!_pools[address(lpToken)], "This liquidity pool is already exist");
    require(lpToken.token0() == address(token) || lpToken.token1() == address(token), "Liquidty pool is invalid");

    _pools[address(lpToken)] = true;

    uint farmId = farms.length;

    farms.push(
      Farm({
        creator: msg.sender,
        token: token,
        lpToken: lpToken,
        id: farmId,
        startsAt: startsAt,
        lastRewardedBlock: block.number + durationInBlocks,
        lpLockTime: lpLockTime,
        numberOfFarmers: 0,
        lpTotalAmount: 0,
        farmersLimit: farmersLimit,
        maxStakePerFarmer: maxStakePerFarmer,
        isActive: true
      })
    );

    emit FarmCreated(farmId);
  }

  // function fastStake(IPancakeRouter router, uint farmId, uint tokenAAmount, uint tokenBAmount) external {
  //   require(tokenAAmount > 0 && tokenBAmount > 0, "Amount must be greater than zero");

  //   Farm storage farm = farms[farmId];
  //   Farmer storage farmer = _farmers[farmId][msg.sender];

  //   IPancakePair pair = farm.lpToken;

  //   IERC20 tokenA = IERC20(pair.token0());
  //   IERC20 tokenB = IERC20(pair.token1());

  //   tokenA.transferFrom(msg.sender, address(this), tokenAAmount);
  //   tokenB.transferFrom(msg.sender, address(this), tokenBAmount);

  //   tokenA.approve(address(router), tokenAAmount);
  //   tokenB.approve(address(router), tokenBAmount);

  //   (uint amountA, uint amountB, uint liquidity) = router.addLiquidity(
  //       address(tokenA),
  //       address(tokenB),
  //       tokenAAmount,
  //       tokenBAmount,
  //       0,
  //       0,
  //       address(this), // send lp tokens directly to this contract
  //       block.timestamp
  //   );

  //   if (tokenAAmount > amountA) {
  //     tokenA.transfer(msg.sender, tokenAAmount - amountA);
  //   }

  //   if (tokenBAmount > amountB) {
  //     tokenB.transfer(msg.sender, tokenBAmount - amountB);
  //   }

  //   _stake(farm, farmer, liquidity, false);
  // }

  // function fastStakeNative(IPancakeRouter router, uint farmId, uint tokenAmount) external payable {
  //   require(tokenAmount > 0, "Amount must be greater than zero");

  //   Farm storage farm = farms[farmId];
  //   Farmer storage farmer = _farmers[farmId][msg.sender];

  //   IPancakePair pair = farm.lpToken;

  //   address WETH = router.WETH();
  //   address tokenA = pair.token0();
  //   address tokenB = pair.token1();
  //   IERC20 token = IERC20(tokenA == WETH ? tokenB : tokenA);

  //   token.transferFrom(msg.sender, address(this), tokenAmount);
  //   token.approve(address(router), tokenAmount);

  //   (uint amountToken, uint amountETH, uint liquidity) = router.addLiquidityETH{value: msg.value}(
  //       address(token),
  //       tokenAmount,
  //       0,
  //       0,
  //       address(this), // send lp tokens directly to this contract
  //       block.timestamp
  //   );

  //   if (tokenAmount > amountToken) {
  //     token.transfer(msg.sender, tokenAmount - amountToken);
  //   }

  //   _stake(farm, farmer, liquidity, false);
  // }
  
  function stake(uint farmId, uint amount) external withLock {
    _stake(farms[farmId], _farmers[farmId][msg.sender], amount);
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

  function _stake(Farm storage farm, Farmer storage farmer, uint amount) internal {
    _stake(farm, farmer, amount, true);
  }

  function _stake(Farm storage farm, Farmer storage farmer, uint amount, bool transferLpTokens) internal {
    require(amount > 0, "Amount must be greater than zero");
    require(farm.isActive, "This farm is inactive or not exist");
    require(block.timestamp >= farm.startsAt, "Yield farming has not started yet for this farm");
    require(block.number <= farm.lastRewardedBlock, "Yield farming is currently closed for this farm");

    uint farmersLimit = farm.farmersLimit;
    uint maxStakePerFarmer = farm.maxStakePerFarmer;

    if (farmersLimit != 0) {
      require(farm.numberOfFarmers <= farmersLimit, "This farm is already full");
    }

    if (maxStakePerFarmer != 0) {
      require(farmer.balance + amount <= maxStakePerFarmer, "You can't stake in this farm, because after that you will be a whale. Sorry :(");
    }
    
    if (transferLpTokens) {
      farm.lpToken.transferFrom(msg.sender, address(this), amount);
    }

    farm.lpTotalAmount += amount;
    farmer.balance += amount;

    if (farmer.startBlock == 0) {
      farm.numberOfFarmers += 1;
      farmer.startBlock = block.number;
      farmer.startTime = block.timestamp;
    }
  }

  function _withdrawLP(Farm storage farm, Farmer storage farmer) internal {
    uint amount = farmer.balance;

    require(amount > 0, "Balance must be greater than zero");

    farm.lpToken.transfer(msg.sender, amount);
    farm.lpTotalAmount -= amount;
    farm.numberOfFarmers -= 1;

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
    uint lpLockTime,
    uint farmersLimit,
    uint maxStakePerFarmer
  ) external {
    Farm storage farm = farms[farmId];

    require(msg.sender == _owner || msg.sender == farm.creator, "Only owner or creator can update this farm");
    require(block.timestamp < farm.startsAt, "You can update only not started farms");

    farm.startsAt = startsAt;
    farm.lastRewardedBlock = lastRewardedBlock;
    farm.lpLockTime = lpLockTime;
    farm.farmersLimit = farmersLimit;
    farm.maxStakePerFarmer = maxStakePerFarmer;
  }

  function setActive(uint farmId, bool value) external onlyOwner {
    farms[farmId].isActive = value;
  }
  
  function setCreationFee(uint _creationFee) external onlyOwner {
    creationFee = _creationFee;
  }

  function withdrawFees() external onlyOwner {
    payable(_owner).transfer(address(this).balance);
  }
}
