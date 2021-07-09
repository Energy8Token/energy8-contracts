pragma solidity ^0.8.0;

abstract contract Ownable {
  address internal _owner;

  modifier onlyOwner() {
    require(_owner == msg.sender, "-_-");
    _;
  }

  constructor() {
    _owner = msg.sender;
  }
}
