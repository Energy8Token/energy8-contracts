pragma solidity 0.5.17;

interface Energy8Token {
  function transfer(address recipient, uint256 amount) external returns (bool);
}

contract Energy8Airdrop {
    address public owner;
    Energy8Token private token = Energy8Token(0x64654f675c06E791e9469Ceee197DD6411080fAd);

    constructor() public {
        owner = msg.sender;
    }
    
    function airdrop(address[] calldata recipients, uint256[] calldata amounts) external {
        require(owner == msg.sender, "Caller is not the owner");

        uint recipientsLength = recipients.length;
        
        for (uint i = 0; i < recipientsLength; i++) {
            token.transfer(recipients[i], amounts[i] * 10**9);
        }
    }
}
