// This contract is under development and has not yet been deployed on mainnet

pragma solidity ^0.8.0;

interface IERC20 {
  function transfer(address recipient, uint256 amount) external returns (bool);
  function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
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
        uint256 tokensLimit;
        uint256 rate;
        uint256 lastRewardBlock;
        uint256 minBlocksForHarvest;
        uint256 totalTokensInFarm;
    }

    struct Farmer {
        uint256 balance;
        uint256 startBlock;
    }

    Farm[] public farms;
    mapping(uint256 => mapping (address => Farmer)) public farmers;

    uint256 totalHarvest;
    uint256 createFarmFee;

    constructor(uint256 _createFarmFee) {
        createFarmFee = _createFarmFee;
    }

    receive() external payable {}

    function createFarm(
        IERC20 _lpToken,
        IERC20 _token,
        uint256 tokensLimit,
        uint256 rate,
        uint256 lastRewardBlock,
        uint256 minBlocksForHarvest
    ) external payable {
        if (msg.sender != owner()) {
            require(msg.value >= createFarmFee);
        }

        farms.push(
            Farm({
                lpToken: _lpToken,
                token: _token,
                tokensLimit: tokensLimit,
                rate: rate,
                lastRewardBlock: lastRewardBlock,
                minBlocksForHarvest: minBlocksForHarvest,
                totalTokensInFarm: 0
            })
        );
    }
    
    function stake(uint256 farmId, uint256 amount) external {
        require(amount > 0, "Amount must be greater than zero");

        Farm storage farm = farms[farmId];
        Farmer storage farmer = farmers[farmId][msg.sender];

        require(block.number < farm.lastRewardBlock && farm.totalTokensInFarm < farm.tokensLimit, "Yield farming is currently closed for this farm");
        
        farm.lpToken.transferFrom(msg.sender, address(this), amount);

        farm.totalTokensInFarm += amount;
        farmer.balance += amount;

        if (farmer.startBlock == 0) {
            farmer.startBlock = block.number;
        }
    }
    
    function harvest(uint256 farmId) external {
        Farm storage farm = farms[farmId];
        Farmer storage farmer = farmers[farmId][msg.sender];

        uint256 startBlock = farmer.startBlock;

        require(startBlock != 0, "You are not a farmer");
        require(block.number >= farmer.startBlock + farm.minBlocksForHarvest, "Too early for harvest");

        uint256 amount = farmer.balance;
        uint256 harvestAmount = amount * _getBlocksRate(farm, startBlock);

        farm.lpToken.transfer(msg.sender, amount);
        farm.token.transfer(msg.sender, harvestAmount);
        
        farm.totalTokensInFarm -= amount;
        totalHarvest += harvestAmount;
        farmer.startBlock = 0;
        farmer.balance = 0;
    }
    
    function yield(uint256 farmId) external view returns (uint256) {
        Farmer storage farmer = farmers[farmId][msg.sender];

        return farmer.balance * _getBlocksRate(farms[farmId], farmer.startBlock);
    }

    function _getBlocksRate(Farm memory farm, uint256 startBlock) internal view returns (uint256) {
        uint256 endBlock = block.number > farm.lastRewardBlock ? farm.lastRewardBlock : block.number;
        uint256 blocksFromStart = endBlock - startBlock;

        return blocksFromStart / farm.rate;
    }
    
    function updateFarm(
        uint256 farmId,
        uint256 tokensLimit,
        uint256 rate,
        uint256 lastRewardBlock,
        uint256 minBlocksForHarvest
    ) external onlyOwner {
        Farm storage farm = farms[farmId];

        farm.tokensLimit = tokensLimit;
        farm.rate = rate;
        farm.lastRewardBlock = lastRewardBlock;
        farm.minBlocksForHarvest = minBlocksForHarvest;
    }
    
    function setCreateFarmFee(uint256 _createFarmFee) external onlyOwner {
        createFarmFee = _createFarmFee;
    }

    function withdrawFees() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }
}
