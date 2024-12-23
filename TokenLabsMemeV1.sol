// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IFactoryWithPair {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint256 value) external returns (bool);
}

/**
 * @title IPair
 * @dev Interface for the pair contract to check totalSupply.
 */
interface IPair {
    function totalSupply() external view returns (uint256);
    function mint(address to) external returns (uint256 liquidity);
}

// Interface for interacting with TokenLabsTokenFactory
interface ITokenLabsTokenFactory {
    function createToken(string memory name, string memory symbol, uint256 initialSupply) external payable returns (address);
    function creationFee() external view returns (uint256);
}

contract TokenLabsMemeV1 is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public tokenFactory; // TokenLabsTokenFactory address
    address public pairFactory;  // Uniswap V2 Factory or similar DEX factory
    address public weth;         // Wrapped ETH token address
    uint256 public additionalFee = 0.0001 ether; // Extra fee for createNewToken

    // Fixed initial supply for all created tokens
    uint256 public constant INITIAL_SUPPLY = 10_000_000_000 * 10 ** 18; // 10 billion tokens, with 18 decimals

    // Evento para la adición de liquidez
    event LiquidityAdded(address indexed tokenAddress, address indexed pair, uint256 tokenAmount, uint256 ethAmount);

    constructor(address _pairFactory, address _weth, address _tokenFactory) Ownable(msg.sender) {
        pairFactory = _pairFactory;
        weth = _weth;
        tokenFactory = _tokenFactory;
    }

    /**
     * @dev Adds liquidity to a DEX by transferring tokens and WETH to the pool.
     * @param tokenA The address of the token being paired.
     */
    function addLiquidityToDEX(
        address tokenA
    ) private {
        // Create the pair between tokenA and WETH
        address pair = IFactoryWithPair(pairFactory).createPair(tokenA, weth);

        // Transfer tokens and WETH to the pair contract
        IERC20(tokenA).safeTransfer(pair, INITIAL_SUPPLY);

        // Deposit ETH as WETH and transfer it to the pair contract
        IWETH(weth).deposit{value: additionalFee}();
        assert(IWETH(weth).transfer(pair, additionalFee));

        // Mint liquidity tokens to complete the liquidity addition
        IPair(pair).mint(address(0));

        // Emit event for liquidity added
        emit LiquidityAdded(tokenA, pair, INITIAL_SUPPLY, additionalFee);
    }

    /**
     * @dev Calls the `createToken` function on TokenLabsTokenFactory to create a new ERC20 token.
     * Requires an additional fee on top of the creation fee from TokenLabsTokenFactory.
     * Adds all tokens and the `additionalFee` as liquidity to the DEX.
     * @param name The name of the new token.
     * @param symbol The symbol of the new token.
     */
    function createNewToken(
        string memory name,
        string memory symbol
    ) external payable returns (address) {
        ITokenLabsTokenFactory factory = ITokenLabsTokenFactory(tokenFactory);

        // Obtain the creation fee from TokenLabsTokenFactory
        uint256 creationFee = factory.creationFee();

        // Calculate total required fee (creationFee + additionalFee)
        uint256 totalRequiredFee = creationFee + additionalFee;
        require(msg.value == totalRequiredFee, "Incorrect total fee amount");

        // Call createToken with the creation fee and fixed initial supply
        address newTokenAddress = factory.createToken{value: creationFee}(name, symbol, INITIAL_SUPPLY);

        // Add liquidity to the DEX with all the created tokens and additionalFee as ETH
        addLiquidityToDEX(newTokenAddress);

        return newTokenAddress;
    }

    /**
     * @notice Sets the additional fee for creating a new token.
     * @param _fee The new additional fee.
     * @dev Only callable by the contract owner.
     */
    function setAdditionalFee(uint256 _fee) external onlyOwner {
        additionalFee = _fee;
    }

    /**
     * @notice Returns the total fees required to create a new token (creationFee + additionalFee).
     * @return The total fees required.
     */
    function getTotalFees() external view returns (uint256) {
        ITokenLabsTokenFactory factory = ITokenLabsTokenFactory(tokenFactory);
        uint256 creationFee = factory.creationFee();
        return creationFee + additionalFee;
    }
}
