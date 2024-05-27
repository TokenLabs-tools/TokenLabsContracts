// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./MyToken.sol";

contract TokenFactory is Ownable(msg.sender) {
    struct TokenInfo {
        string name;
        string symbol;
        address creator;
        uint256 creationDate;
        uint256 initialSupply;
        string imageUrl;
        bool isBurnable;
        bool isMintable;
    }

    mapping(address => TokenInfo) public tokenInfo;
    mapping(address => address[]) public tokensCreatedBy;
    uint256 public creationFee = 0.0001 ether;

    event TokenCreated(
        address indexed tokenAddress,
        string name,
        string symbol,
        address creator,
        uint256 creationDate,
        uint256 initialSupply,
        string imageUrl,
        bool isBurnable,
        bool isMintable
    );

    function setCreationFee(uint256 _fee) public onlyOwner {
        creationFee = _fee;
    }

    function createToken(
        string memory name, 
        string memory symbol, 
        uint256 initialSupply, 
        string memory imageUrl,
        bool isRenonced,
        bool isMintable
    ) public payable returns (address newTokenAddress){
        require(msg.value >= creationFee, "Creation fee is not met");

        bool isBurnable = true;

        MyToken newToken = new MyToken(name, symbol, msg.sender, initialSupply, isBurnable, isMintable); // Ajustar el constructor de MyToken

        if (isRenonced){
            newToken.renounceOwnership();
        }else{
            newToken.transferOwnership(msg.sender);
        }
        
        tokenInfo[address(newToken)] = TokenInfo(
            name,
            symbol,
            msg.sender,
            block.timestamp,
            initialSupply,
            imageUrl,
            isBurnable,
            isMintable
        );

        tokensCreatedBy[msg.sender].push(address(newToken));

        emit TokenCreated(
            address(newToken),
            name,
            symbol,
            msg.sender,
            block.timestamp,
            initialSupply,
            imageUrl,
            isBurnable,
            isMintable
        );

        payable(owner()).transfer(creationFee);
        if (msg.value > creationFee) {
            payable(msg.sender).transfer(msg.value - creationFee);
        }

        return address(newToken);

    }

    function getCreatedTokens(address creator) public view returns (address[] memory) {
        return tokensCreatedBy[creator];
    }

    function withdraw() public onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
}
