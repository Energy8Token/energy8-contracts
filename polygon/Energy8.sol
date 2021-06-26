pragma solidity ^0.8.0;

interface IERC20 {
  function name() external view returns (string memory);
  function symbol() external view returns (string memory);
  function decimals() external view returns (uint8);
  function totalSupply() external view returns (uint256);
  function balanceOf(address account) external view returns (uint256);
  function allowance(address owner, address spender) external view returns (uint256);
  
  function transfer(address recipient, uint256 amount) external returns (bool);
  function approve(address spender, uint256 amount) external returns (bool);
  function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
  
  event Transfer(address indexed from, address indexed to, uint256 value);
  event Approval(address indexed owner, address indexed spender, uint256 value);
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

interface IFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IRouter {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

contract Energy8 is IERC20, Ownable {
  mapping (address => mapping (address => uint256)) private _allowances;
  mapping (address => uint256) private _balances;
  mapping (address => uint256) private _startPeriodBalances;
  mapping (address => uint256) private _spentDuringPeriod;
  mapping (address => uint256) private _periodStartTime;
  mapping (address => bool) private _whitelist;
  mapping (address => bool) private _blacklist;
  mapping (address => bool) private _sellers;
  mapping (address => bool) public admins;

  string private _name = "Energy 8";
  string private _symbol = "E8";
  
  uint256 private _totalSupply = 100000000000000 * 10**9; // 200 000 000 000 000
  uint256 public periodDuration = 1 days;
  uint256 public minTokensForLiquidityGeneration = _totalSupply / 1000000; // 0.001% of total supply
  
  /*
    10000 - 100%
    1000 - 10%
    100 - 1%
    10 - 0.1%
    1 - 0.01%
  */
  // transfer fees
  uint16 fee = 0;
  uint16 buyFee = 0;
  uint16 sellFee = 0;
  uint16 liquidityFee = 0;
  uint16 sellLiquidityFee = 0;
  uint16 buyLiquidityFee = 0;
  uint16 adminFee = 0;
  
  uint16 public maxTransferPercent = 3000; // 30%
  uint16 public maxHodlPercent = 100; // 1%
  uint8 private _decimals = 9;
  
  // AMM addresses
  IRouter public router;
  address public pair;
  address private mainTokenInPair;
  
  bool generateLiquidityEnabled = true;
  
  modifier onlyAdmin() {
    require(admins[msg.sender], "Who are you?");
    _;
  }
  
  bool isLocked;

  modifier lock {
    isLocked = true;
    _;
    isLocked = false;
  }

  constructor(IRouter _router) {
    _balances[msg.sender] = _totalSupply;

    _approve(address(this), address(_router), _totalSupply);
    
    mainTokenInPair = _router.WETH();
    
    pair = IFactory(_router.factory()).createPair(address(this), mainTokenInPair);
    
    // add owner and this contract to the whitelist for disable transfer limitations and fees
    _whitelist[msg.sender] = true;
    _whitelist[address(this)] = true;

    _sellers[pair] = true;
    _sellers[address(_router)] = true;

    admins[msg.sender] = true;
    
    emit Transfer(address(0), msg.sender, _totalSupply);
  }

  function getOwner() external view returns (address) {
    return owner();
  }

  function decimals() external view override returns (uint8) {
    return _decimals;
  }

  function symbol() external view override returns (string memory) {
    return _symbol;
  }

  function name() external view override returns (string memory)  {
    return _name;
  }

  function totalSupply() external view override returns (uint256) {
    return _totalSupply;
  }
  
  function balanceOf(address account) external view override returns (uint256) {
    return _balances[account];
  }

  function transfer(address recipient, uint256 amount) external override returns (bool) {
    _transfer(msg.sender, recipient, amount);
    return true;
  }

  function allowance(address owner, address spender) external view override returns (uint256) {
    return _allowances[owner][spender];
  }

  function approve(address spender, uint256 amount) external override returns (bool) {
    _approve(msg.sender, spender, amount);
    return true;
  }

  function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
    uint256 currentAllowance = _allowances[sender][msg.sender];
    require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
    _transfer(sender, recipient, amount);
    unchecked {
        _approve(sender, msg.sender, currentAllowance - amount);
    }

    return true;
  }
  
  function _approve(address owner, address spender, uint256 amount) internal {
    require(owner != address(0), "ERC20: approve from the zero address");
    require(spender != address(0), "ERC20: approve to the zero address");

    _allowances[owner][spender] = amount;
    emit Approval(owner, spender, amount);
  }
  
  receive() external payable {}

  function _transfer(address sender, address recipient, uint256 amount) internal {
    require(sender != address(0), "ERC20: transfer from the zero address");
    require(recipient != address(0), "ERC20: transfer to the zero address");
    require(sender != recipient, "The sender cannot be the recipient");
    require(amount > 0, "Transfer amount must be greater than zero");
    
    uint256 feeInTokens;
    uint256 liquidityFeeInTokens;

    // buy tokens
    if (_sellers[sender]) {
      if (!_whitelist[recipient]) {
        feeInTokens = _getPercentage(amount, buyFee);
        liquidityFeeInTokens = _getPercentage(amount, buyLiquidityFee);

        unchecked {
            _checkHodlPercent(recipient, amount - feeInTokens - liquidityFeeInTokens, "You cannot hold more tokens. You are already a whale!");
        }
      }
    // sell tokens
    } else if (_sellers[recipient]) {
      require(!_blacklist[sender], "You are blacklisted and cannot sell tokens :(");

      if (!_whitelist[sender]) {
        feeInTokens = _getPercentage(amount, sellFee);
        liquidityFeeInTokens = _getPercentage(amount, sellLiquidityFee);

        unchecked {
            _checkAndUpdatePeriod(sender, amount - feeInTokens - liquidityFeeInTokens, "You can no longer sell tokens for the current period. Just relax and wait");
        }
      }
    // transfer tokens between addresses
    } else {
      require(!_blacklist[sender] && !_blacklist[msg.sender], "You are blacklisted and cannot transfer tokens :(");

      if (!_whitelist[sender] || !_whitelist[msg.sender]) {
        feeInTokens = _getPercentage(amount, fee);
        liquidityFeeInTokens = _getPercentage(amount, liquidityFee);

        unchecked {
            uint256 transferAmount = amount - feeInTokens - liquidityFeeInTokens;

            _checkHodlPercent(recipient, transferAmount, "Recipient cannot hold more tokens. He's already a whale!");
            _checkAndUpdatePeriod(sender, transferAmount, "You can no longer transfer tokens for the current period. Just relax and wait");
        }
      }
    }
    
    uint256 adminFeeInTokens = _getPercentage(amount, adminFee);

    uint256 contractTokenBalance = _balances[address(this)];

    unchecked {
        amount -= feeInTokens - liquidityFeeInTokens - adminFeeInTokens;
    }
    
    if (adminFeeInTokens > 0) {
        _balances[owner()] += adminFeeInTokens;
    }
    
    uint256 senderBalance = _balances[sender];
    require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
    unchecked {
        _balances[sender] = senderBalance - amount;
    }
    _balances[recipient] += amount;
    
    if (generateLiquidityEnabled && !isLocked && liquidityFeeInTokens > 0 && !_sellers[sender]) {
        contractTokenBalance += liquidityFeeInTokens;
        _balances[address(this)] = contractTokenBalance;

        if (contractTokenBalance >= minTokensForLiquidityGeneration) {
            generateLiquidity(contractTokenBalance);
        }
    }

    emit Transfer(sender, recipient, amount);
  }
  
  function generateLiquidity(uint256 amount) internal lock {
    unchecked {
        uint256 tokensForSell = amount / 2;
        uint256 tokensForLiquidity = amount - tokensForSell;
    
        uint256 initialBalance = address(this).balance;
    
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = mainTokenInPair;
    
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokensForSell,
            0, // accept any amount
            path,
            address(this),
            block.timestamp
        );
        
        uint256 balance = address(this).balance - initialBalance;
        
        router.addLiquidityETH{value: balance}(
            address(this),
            tokensForLiquidity,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            0x000000000000000000000000000000000000dEaD,
            block.timestamp
        );
    }
  }
  
  function _checkAndUpdatePeriod(address account, uint256 amount, string memory errorMessage) internal {
    bool _isPeriodEnd = block.timestamp > (_periodStartTime[account] + periodDuration);

    if (_isPeriodEnd) {
        _periodStartTime[account] = block.timestamp;
        _startPeriodBalances[account] = _balances[account];
        _spentDuringPeriod[account] = 0;
    }

    uint256 newSoldDuringPeriod = _spentDuringPeriod[account] + amount;
    uint256 oneCanSolOrTransfer = _getPercentage(_startPeriodBalances[account], maxTransferPercent);
    
    require(newSoldDuringPeriod <= oneCanSolOrTransfer, errorMessage);
    
    _spentDuringPeriod[account] = newSoldDuringPeriod;
  }
  
  function _getPercentage(uint256 number, uint16 percent) internal pure returns (uint256) {
    return (number * percent) / 10000;
  }
  
  function _checkHodlPercent(address account, uint256 amount, string memory erorrMessage) internal view {
    uint256 oneAccountCanHodl = _getPercentage(_totalSupply, maxHodlPercent);

    require((_balances[account] + amount) <= oneAccountCanHodl, erorrMessage);
  }
  
  function setSeller(address account, bool value) external onlyAdmin {
    _sellers[account] = value;
  }
  
  function setWhitelist(address account, bool value) external onlyAdmin {
    _whitelist[account] = value;
  }
  
  function setBlacklist(address account, bool value) external onlyAdmin {
    _blacklist[account] = value;
  }
  
  function setAdmin(address account, bool value) external onlyOwner {
    admins[account] = value;
  }
  
  function setMaxHodlPercent(uint16 percent) external onlyAdmin {
    require(percent > 0 && percent <= 10000); // >0% - 100%
    maxHodlPercent = percent;
  }
  
  function setMaxTransferPercent(uint16 percent) external onlyAdmin {
    require(percent >= 100 && percent <= 10000); // 1% - 100%
    maxTransferPercent = percent;
  }
  
  function setPeriodDuration(uint time) external onlyAdmin {
    require(time <= 14 days);
    periodDuration = time;
  }
  
  function isSeller(address account) external view returns (bool) {
      return _sellers[account];
  }
  
  function isWhitelisted(address account) external view returns (bool) {
      return _whitelist[account];
  }
  
  function isBlacklisted(address account) external view returns (bool) {
      return _blacklist[account];
  }
  
  function getAccountPeriodInfo(address account) external view returns (uint256 startBalance, uint256 startTime, uint256 spent) {
      startBalance = _startPeriodBalances[account];
      startTime = _periodStartTime[account];
      spent = _spentDuringPeriod[account];
  }
  
  function setRouter(IRouter _router) external onlyOwner {
      router = _router;
  }
  
  function setPair(address _pair) external onlyOwner {
      pair = _pair;
  }
  
  function setMainTokenInPair(address token) external onlyOwner {
      mainTokenInPair = token;
  }
  
  function setMinTokensForLiquidityGeneration(uint256 amount) external onlyOwner {
      minTokensForLiquidityGeneration = amount;
  }
  
  function setTransferFees(uint16 _fee, uint16 _buyFee, uint16 _sellFee) external onlyOwner {
    require(
        _fee <= 1000 && // 0% - 10%
        _buyFee <= 1000 && // 0% - 10%
        _sellFee <= 1000 // 0% - 10%
    );
    fee = _fee;
    buyFee = _buyFee;
    sellFee = _sellFee;
  }
  
  function setLiquidityFees(uint16 _liquidityFee, uint16 _buyLiquidityFee, uint16 _sellLiquidityFee) public onlyOwner {
    require(
        _liquidityFee <= 1000 && // 0% - 10%
        _buyLiquidityFee <= 1000 && // 0% - 10%
        _sellLiquidityFee <= 1000 // 0% - 10%
    );
    liquidityFee = _liquidityFee;
    buyLiquidityFee = _buyLiquidityFee;
    sellLiquidityFee = _sellLiquidityFee;
  }
  
  function setAdminFee(uint16 _adminFee) external onlyOwner {
    require(_adminFee <= 500); // 0% - 5%
    adminFee = _adminFee;
  }
  
  function enableLiquidityGeneration(uint16 _liquidityFee, uint16 _buyLiquidityFee, uint16 _sellLiquidityFee) external onlyOwner {
      generateLiquidityEnabled = false;
      setLiquidityFees(_liquidityFee, _buyLiquidityFee, _sellLiquidityFee);
  }
  
  function disableLiquidityGeneration() external onlyOwner {
      generateLiquidityEnabled = false;
      setLiquidityFees(0, 0, 0);
  }
  
  function _getPercentage(uint256 number, uint8 percent) internal pure returns (uint256) {
    return (number * percent) / 10000;
  }
}
