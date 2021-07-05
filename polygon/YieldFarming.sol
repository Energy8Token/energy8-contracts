// This contract is under development and has not yet been deployed on mainnet

pragma solidity ^0.8.0;

interface IERC20 {
  function transfer(address recipient, uint256 amount) external returns (bool);
  function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract YieldFarming {
    mapping(address => uint256) private farmerBalances;
    mapping(address => uint256) private farmerStartBlock;
    
    uint256 public maxTokensInFarm = 7000000000000 * 10**9; // 7 000 000 000 000
    uint256 public rate = 86400;
    
    uint256 private constant AVERAGE_BLOCKS_PER_DAY = 41000; // average number of blocks created per day in the Polygon network

    uint256 public lastRewardBlock = block.number + AVERAGE_BLOCKS_PER_DAY * 60; // ~2 month
    uint256 public minBlocksForHarvest = AVERAGE_BLOCKS_PER_DAY * 7; // ~7 day

    uint256 public totalTokensInFarm;
    uint256 public totalHarvest;
    
    address private owner;
    IERC20 private token;
    
    modifier onlyOwner() {
        require(owner == msg.sender, "-_-");
        _;
    }
    
    constructor(IERC20 _token) {
        owner = msg.sender;
        token = _token;
    }
    
    function farm(uint256 amount) external {
        require(amount > 0, "Amount must be greater than zero");
        require(block.number < lastRewardBlock && totalTokensInFarm < maxTokensInFarm, "Yield farming is currently closed");
        
        token.transferFrom(msg.sender, address(this), amount);
        
        if (farmerBalances[msg.sender] == 0) {
            farmerStartBlock[msg.sender] = block.number;
        }
        
        farmerBalances[msg.sender] += amount;
        totalTokensInFarm += amount;
    }
    
    function harvest() external {
        require(block.number >= farmerStartBlock[msg.sender] + minBlocksForHarvest, "Too early for harvest");

        uint256 amount = farmerBalances[msg.sender];
        uint256 harvestAmount = _yield(msg.sender);

        token.transfer(msg.sender, amount + harvestAmount);
        
        totalHarvest += harvestAmount;
        farmerStartBlock[msg.sender] = 0;
        farmerBalances[msg.sender] = 0;
        totalTokensInFarm -= amount;
    }
    
    function yield(address account) external view returns (uint256) {
        return _yield(account);
    }
    
    function yield() external view returns (uint256) {
        return _yield(msg.sender);
    }
    
    function _yield(address account) internal view returns (uint256) {
        uint256 startBlock = farmerStartBlock[account];
        
        require(startBlock > 0, "This account are not a farmer");
        
        uint256 endBlock = block.number > lastRewardBlock ? lastRewardBlock : block.number;
        uint256 blocksFromStart = endBlock - startBlock;
        uint256 blocksRate = blocksFromStart / rate;
        
        return farmerBalances[account] * blocksRate;
    }
    
    function updateLastRewardBlock(uint256 _lastRewardBlock) external onlyOwner {
        lastRewardBlock = _lastRewardBlock;
    }
    
    function updateMinBlocksForHarvest(uint256 _minBlocksForHarvest) external onlyOwner {
        minBlocksForHarvest = _minBlocksForHarvest;
    }
    
    function updateMaxTokensInFarm(uint256 _maxTokensInFarm) external onlyOwner {
        maxTokensInFarm = _maxTokensInFarm;
    }
    
    function updateRate(uint256 _rate) external onlyOwner {
        rate = _rate;
    }

    function isFarmer(address account) external view returns (bool) {
        return farmerBalances[account] > 0;
    }
}
