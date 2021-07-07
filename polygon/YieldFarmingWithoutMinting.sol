// This contract is under development and has not yet been deployed on mainnet

pragma solidity ^0.8.0;

interface IERC20 {
  function balanceOf(address account) external view returns (uint256);
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

contract YieldFarmingWithoutMinting is Ownable {
    struct Farm {
        IERC20 lpToken;
        IERC20 token;
        uint startFromBlock;
        uint lastRewardedBlock;
        uint minBlocksForHarvest;
        uint totalLp;
        uint numberOfFarmers;
    }

    struct Farmer {
        uint balance;
        uint startBlock;
    }

    Farm[] public farms;
    mapping(uint => mapping (address => Farmer)) private farmers;

    uint public creatingFee;

    constructor(uint _creatingFee) {
        creatingFee = _creatingFee;
    }

    receive() external payable {}

    function createFarm(
        IERC20 lpToken,
        IERC20 token,
        uint startFromBlock,
        uint lastRewardedBlock,
        uint minBlocksForHarvest
    ) external payable {
        if (msg.sender != owner()) {
            require(msg.value >= creatingFee);
        }

        farms.push(
            Farm(
                lpToken,
                token,
                // allocatedTokens,
                startFromBlock,
                lastRewardedBlock,
                minBlocksForHarvest,
                0,
                0
            )
        );
    }
    
    function stake(uint farmId, uint amount) external {
        require(amount > 0, "Amount must be greater than zero");

        Farm storage farm = farms[farmId];
        Farmer storage farmer = farmers[farmId][msg.sender];

        require(block.number > farm.startFromBlock, "Yield farming has not started yet for this farm");
        require(block.number < farm.lastRewardedBlock, "Yield farming is currently closed for this farm");
        
        farm.lpToken.transferFrom(msg.sender, address(this), amount);
        farm.totalLp += amount;
        farmer.balance += amount;

        if (farmer.startBlock == 0) {
            farm.numberOfFarmers += 1;
            farmer.startBlock = block.number;
        }
    }

    function harvest(uint farmId) external {
        Farm storage farm = farms[farmId];
        Farmer storage farmer = farmers[farmId][msg.sender];

        uint startBlock = farmer.startBlock;

        require(startBlock != 0, "You are not a farmer");
        require(block.number >= startBlock + farm.minBlocksForHarvest, "Too early for harvest");

        uint amount = farmer.balance;
        uint harvestAmount = _calculateYield(farm, amount, startBlock);

        farm.token.transfer(msg.sender, harvestAmount);
    }

    function withdraw(uint farmId) external {
        Farm storage farm = farms[farmId];
        Farmer storage farmer = farmers[farmId][msg.sender];

        uint startBlock = farmer.startBlock;
        
        require(startBlock != 0, "You are not a farmer");
        require(block.number >= startBlock + farm.minBlocksForHarvest, "Too early for harvest");

        uint amount = farmer.balance;
        uint harvestAmount = _calculateYield(farm, amount, startBlock);

        farm.lpToken.transfer(msg.sender, amount);
        farm.token.transfer(msg.sender, harvestAmount);
        
        farm.totalLp -= amount;
        farmer.startBlock = 0;
        farmer.balance = 0;
    }

    /*
        withdraw lp tokens without a reward
    */
    function emergencyWithdraw(uint farmId) external {
        Farm storage farm = farms[farmId];
        Farmer storage farmer = farmers[farmId][msg.sender];

        uint amount = farmer.balance;

        farm.lpToken.transfer(msg.sender, amount);
        
        farm.totalLp -= amount;
        farmer.startBlock = 0;
        farmer.balance = 0;
    }
    
    function yield(uint farmId) external view returns (uint) {
        Farmer storage farmer = farmers[farmId][msg.sender];

        return _calculateYield(farms[farmId], farmer.balance, farmer.startBlock);
    }

    function _calculateYield(Farm memory farm, uint balance, uint fromBlock) internal view returns (uint) {
        if (farm.totalLp == 0 || fromBlock == 0) {
            return 0;
        }

        uint rewardedBlocks = block.number - fromBlock;
        uint tokensPerFarmer = (rewardedBlocks * farm.lpToken.balanceOf(address(this))) / farm.lastRewardedBlock;
        uint balanceRate = (balance * 10**9) / farm.totalLp;
    
        return (tokensPerFarmer * balanceRate) / 10**9;
    }
    
    function updateFarm(
        uint farmId,
        uint startFromBlock,
        uint lastRewardedBlock,
        uint minBlocksForHarvest
    ) external onlyOwner {
        Farm storage farm = farms[farmId];

        farm.startFromBlock = startFromBlock;
        farm.lastRewardedBlock = lastRewardedBlock;
        farm.minBlocksForHarvest = minBlocksForHarvest;
    }
    
    function setCreatingFee(uint _creatingFee) external onlyOwner {
        creatingFee = _creatingFee;
    }

    function withdrawFees() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }
}
