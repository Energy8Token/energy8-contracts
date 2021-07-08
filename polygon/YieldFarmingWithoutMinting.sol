// This contract is under development and has not yet been deployed on mainnet

pragma solidity ^0.8.0;

interface IERC20 {
  function balanceOf(address account) external view returns (uint256);
  function transfer(address recipient, uint amount) external returns (bool);
}

interface IPancakePair {
  function token0() external view returns (address);
  function token1() external view returns (address);
  function balanceOf(address owner) external view returns (uint);
  function transfer(address recipient, uint amount) external returns (bool);
  function transferFrom(address sender, address recipient, uint amount) external returns (bool);
}

abstract contract Ownable {
  address private _owner;

  modifier onlyOwner() {
    require(_owner == msg.sender, "-_-");
    _;
  }

  constructor() {
    _owner = msg.sender;
  }

  function owner() internal view returns (address) {
    return _owner;
  }
}

abstract contract Lockable {
  bool private unlocked = true;

  modifier withLock() {
    require(unlocked, 'Call locked');
    unlocked = false;
    _;
    unlocked = true;
  }
}

contract YieldFarmingWithoutMinting is Ownable, Lockable {
  struct Farm {
    IERC20 token;
    IPancakePair lpToken;
    uint startsAt;
    uint lastRewardedBlock;
    uint minBlocksForHarvest;
    uint timeLimit;
    uint amountLimit;
    uint numberOfFarmers;
    bool isActive;
  }

  struct Farmer {
    uint balance;
    uint startBlock;
  }

  Farm[] public farms;
  mapping(uint => mapping (address => Farmer)) private farmers;

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
    uint minBlocksForHarvest,
    uint timeLimit,
    uint amountLimit
  ) external payable {
    if (msg.sender != owner()) {
      require(msg.value >= creationFee);
    }

    address token0 = lpToken.token0();
    address token1 = lpToken.token1();

    require(token0 == address(token) || token1 == address(token));

    farms.push(
      Farm(
        token,
        lpToken,
        startsAt,
        lastRewardedBlock,
        minBlocksForHarvest,
        timeLimit,
        amountLimit,
        0,
        true
      )
    );
  }
  
  function stake(uint farmId, uint amount) external {
    require(amount > 0, "Amount must be greater than zero");

    Farm storage farm = farms[farmId];
    Farmer storage farmer = farmers[farmId][msg.sender];

    require(farm.isActive, "This farm is inactive or not exist");
    require(block.timestamp > farm.startsAt, "Yield farming has not started yet for this farm");
    require(block.number < farm.lastRewardedBlock, "Yield farming is currently closed for this farm");
    
    farm.lpToken.transferFrom(msg.sender, address(this), amount);
    farmer.balance += amount;

    if (farmer.startBlock == 0) {
      farm.numberOfFarmers += 1;
      farmer.startBlock = block.number;
    }
  }

  function harvest(uint farmId) external withLock {
    Farm storage farm = farms[farmId];
    Farmer storage farmer = farmers[farmId][msg.sender];

    uint startBlock = farmer.startBlock;

    require(startBlock != 0, "You are not a farmer");
    require(block.number >= startBlock + farm.minBlocksForHarvest, "Too early for harvest");

    uint amount = farmer.balance;
    uint harvestAmount = _calculateYield(farm, amount, startBlock);

    farm.token.transfer(msg.sender, harvestAmount);
  }

  function withdraw(uint farmId) external withLock {
    Farm storage farm = farms[farmId];
    Farmer storage farmer = farmers[farmId][msg.sender];

    uint startBlock = farmer.startBlock;
    
    require(startBlock != 0, "You are not a farmer");
    require(block.number >= startBlock + farm.minBlocksForHarvest, "Too early for harvest");

    uint amount = farmer.balance;
    uint harvestAmount = _calculateYield(farm, amount, startBlock);

    farm.lpToken.transfer(msg.sender, amount);
    farm.token.transfer(msg.sender, harvestAmount);
    farm.numberOfFarmers -= 1;

    farmer.startBlock = 0;
    farmer.balance = 0;
  }

  /*
      withdraw lp tokens without a reward
  */
  function emergencyWithdraw(uint farmId) external withLock {
    Farm storage farm = farms[farmId];
    Farmer storage farmer = farmers[farmId][msg.sender];

    uint amount = farmer.balance;

    require(amount > 0, "Amount must be greater than zero");

    farm.lpToken.transfer(msg.sender, amount);
    farm.numberOfFarmers -= 1;
    farmer.startBlock = 0;
    farmer.balance = 0;
  }
  
  function yield(uint farmId) external view returns (uint) {
    Farmer storage farmer = farmers[farmId][msg.sender];

    return _calculateYield(farms[farmId], farmer.balance, farmer.startBlock);
  }

  function _calculateYield(Farm memory farm, uint balance, uint fromBlock) internal view returns (uint) {
    uint lpBalance = farm.lpToken.balanceOf(address(this));

    if (lpBalance == 0 || fromBlock == 0) {
      return 0;
    }

    uint rewardedBlocks = block.number - fromBlock;
    uint tokensPerFarmer = (rewardedBlocks * farm.token.balanceOf(address(this))) / farm.lastRewardedBlock;
    uint balanceRate = (balance * 10**9) / lpBalance;

    return (tokensPerFarmer * balanceRate) / 10**9;
  }
  
  function updateFarm(
    uint farmId,
    uint startsAt,
    uint lastRewardedBlock,
    uint minBlocksForHarvest
  ) external onlyOwner {
    Farm storage farm = farms[farmId];

    farm.startsAt = startsAt;
    farm.lastRewardedBlock = lastRewardedBlock;
    farm.minBlocksForHarvest = minBlocksForHarvest;
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
