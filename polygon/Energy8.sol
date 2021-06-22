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
  
  uint256 private _totalSupply = 200000000000000 * 10**9; // 200 000 000 000 000
  uint256 public periodDuration = 1 days;
  
  /*
    10000 - 100%
    1000 - 10%
    100 - 1%
    10 - 0.1%
    1 - 0.01%
  */
  uint16 public maxTransferPercent = 3000; // 30%
  uint16 public maxHodlPercent = 100; // 1%
  uint8 private _decimals = 9;
  
  modifier onlyAdmin() {
    require(admins[msg.sender], "Who are you?");
    _;
  }

  constructor() {
    _balances[msg.sender] = _totalSupply;
    
    // add owner and this contract to the whitelist for disable transfer limitations
    _whitelist[msg.sender] = true;
    _whitelist[address(this)] = true;

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
  
  function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
    _approve(msg.sender, spender, _allowances[msg.sender][spender] + addedValue);
    return true;
  }

  function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
    uint256 currentAllowance = _allowances[msg.sender][spender];
    require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
    unchecked {
        _approve(msg.sender, spender, currentAllowance - subtractedValue);
    }

    return true;
  }
  
  function _approve(address owner, address spender, uint256 amount) internal {
    require(owner != address(0), "ERC20: approve from the zero address");
    require(spender != address(0), "ERC20: approve to the zero address");

    _allowances[owner][spender] = amount;
    emit Approval(owner, spender, amount);
  }

  function _transfer(address sender, address recipient, uint256 amount) internal {
    require(sender != address(0), "ERC20: transfer from the zero address");
    require(recipient != address(0), "ERC20: transfer to the zero address");
    require(sender != recipient, "The sender cannot be the recipient");
    require(amount > 0, "Transfer amount must be greater than zero");

    // buy tokens
    if (_sellers[sender]) {
      if (!_whitelist[recipient]) {
        _checkHodlPercent(recipient, amount, "You cannot hold more tokens. You are already a whale!");
      }
    // sell tokens
    } else if (_sellers[recipient]) {
      require(!_blacklist[sender], "You are blacklisted and cannot sell tokens :(");

      if (!_whitelist[sender]) {
        _checkAndUpdatePeriod(sender, amount, "You can no longer sell tokens for the current period. Just relax and wait");
      }
    // transfer tokens between addresses
    } else {
      require(!_blacklist[sender] && !_blacklist[msg.sender], "You are blacklisted and cannot transfer tokens :(");

      if (!_whitelist[sender] || !_whitelist[msg.sender]) {
        _checkHodlPercent(recipient, amount, "Recipient cannot hold more tokens. He's already a whale!");

        _checkAndUpdatePeriod(sender, amount, "You can no longer transfer tokens for the current period. Just relax and wait");
      }
    }
    
    uint256 senderBalance = _balances[sender];
    require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
    unchecked {
        _balances[sender] = senderBalance - amount;
    }
    _balances[recipient] += amount;

    emit Transfer(sender, recipient, amount);
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
  
  function setMaxHodlPercent(uint16 newPercent) external onlyAdmin {
    require(newPercent >= 0 && newPercent <= 10000);
    maxHodlPercent = newPercent;
  }
  
  function setMaxTransferPercent(uint16 newPercent) external onlyAdmin {
    require(newPercent >= 0 && newPercent <= 10000);
    maxTransferPercent = newPercent;
  }
  
  function setPeriodDuration(uint newTime) external onlyAdmin {
    periodDuration = newTime;
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
}
