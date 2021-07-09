pragma solidity ^0.8.0;

abstract contract Lockable {
  bool private unlocked = true;

  modifier withLock() {
    require(unlocked, 'Call locked');
    unlocked = false;
    _;
    unlocked = true;
  }
}
