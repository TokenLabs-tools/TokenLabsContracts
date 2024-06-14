// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract TokenLabsTokenFactory is Ownable(msg.sender) {
    struct TokenInfo {string name; string symbol; address creator; uint256 creationDate; uint256 initialSupply; string imageUrl;}

    mapping(address => TokenInfo) public tokenInfo;
    mapping(address => address[]) public tokensCreatedBy;
    uint256 public creationFee = 0.0001 ether;

    event TokenCreated(address indexed tokenAddress, string name, string symbol, address creator, uint256 creationDate, uint256 initialSupply, string imageUrl);

    function setCreationFee(uint256 _fee) public onlyOwner { creationFee = _fee; }

    function createToken(string memory name, string memory symbol, uint256 initialSupply, string memory imageUrl) public payable returns (address newTokenAddress){
        require(msg.value >= creationFee, "Creation fee is not met");

        ERCToken newToken = new ERCToken(name, symbol, msg.sender, initialSupply); // Ajustar el constructor de ERCToken
        
        tokenInfo[address(newToken)] = TokenInfo(name,symbol,msg.sender,block.timestamp,initialSupply,imageUrl);

        tokensCreatedBy[msg.sender].push(address(newToken));

        emit TokenCreated(address(newToken),name,symbol,msg.sender,block.timestamp,initialSupply,imageUrl);

        payable(owner()).transfer(creationFee);
        if (msg.value > creationFee) { payable(msg.sender).transfer(msg.value - creationFee); }

        return address(newToken);

    }

    function getCreatedTokens(address creator) public view returns (address[] memory) { return tokensCreatedBy[creator]; }
    
}

contract ERCToken is ERC20, ERC20Burnable {
    constructor(string memory name, string memory symbol, address creator, uint256 initialSupply) ERC20(name, symbol) { _mint(creator, initialSupply); }
}