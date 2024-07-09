// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title TokenLabsTokenFactory
 * @dev This contract allows users to create their own ERC20 tokens with a specified initial supply. 
 *      It charges a fee for token creation.
 */
contract TokenLabsTokenFactory is Ownable(msg.sender), ReentrancyGuard {
    struct TokenInfo {string name; string symbol; address creator; uint256 creationDate; uint256 initialSupply;}

    mapping(address => TokenInfo) public tokenInfo;
    mapping(address => address[]) public tokensCreatedBy;
    uint256 public creationFee = 0.0001 ether;

    event TokenCreated(address indexed tokenAddress, string name, string symbol, address creator, uint256 creationDate, uint256 initialSupply);

    /**
     * @notice Sets the fee for creating a new token.
     * @param _fee The new creation fee.
     * @dev Only callable by the contract owner.
     */
    function setCreationFee(uint256 _fee) public onlyOwner { creationFee = _fee; }

    /**
     * @notice Creates a new ERC20 token.
     * @param name The name of the token.
     * @param symbol The symbol of the token.
     * @param initialSupply The initial supply of the token.
     * @return newTokenAddress The address of the newly created token.
     * @dev Requires a fee to be paid. The fee is transferred to the contract owner. Excess fee is refunded to the sender.
     */
    function createToken(string memory name, string memory symbol, uint256 initialSupply) public payable nonReentrant returns (address newTokenAddress) {
        require(msg.value >= creationFee, "Creation fee is not met");
        require(initialSupply >= 1, "Initial supply must be at least 1");

        (bool sent, ) = owner().call{value: msg.value}("");
        require(sent, "Transfer failed");

        ERCToken newToken = new ERCToken(name, symbol, msg.sender, initialSupply); // Adjust the constructor of ERCToken
        
        tokenInfo[address(newToken)] = TokenInfo(name, symbol, msg.sender, block.timestamp, initialSupply);

        tokensCreatedBy[msg.sender].push(address(newToken));

        emit TokenCreated(address(newToken), name, symbol, msg.sender, block.timestamp, initialSupply);

        if (msg.value > creationFee) {
            (bool refundSent, ) = msg.sender.call{value: msg.value - creationFee}("");
            require(refundSent, "Refund transfer failed");
        }

        return address(newToken);
    }

    /**
     * @notice Returns the list of tokens created by a specific address.
     * @param creator The address of the token creator.
     * @return An array of token addresses created by the specified creator.
     */
    function getCreatedTokens(address creator) public view returns (address[] memory) { return tokensCreatedBy[creator]; }
    
}

/**
 * @title ERCToken
 * @dev Implementation of the ERC20 token with burnable feature.
 */
contract ERCToken is ERC20, ERC20Burnable {
    /**
     * @dev Initializes the token with the given parameters and mints the initial supply to the creator.
     * @param name The name of the token.
     * @param symbol The symbol of the token.
     * @param creator The address of the token creator.
     * @param initialSupply The initial supply of the token.
     */
    constructor(string memory name, string memory symbol, address creator, uint256 initialSupply) ERC20(name, symbol) { 
        _mint(creator, initialSupply); 
    }
}
