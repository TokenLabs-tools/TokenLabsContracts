// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title TokenLabsLock
 * @dev This contract locks ERC20 tokens until a specified release time.
 */
contract TokenLabsLock {
    using SafeERC20 for IERC20;
    IERC20 public token;
    address public beneficiary;
    uint256 public releaseTime;
    uint256 public lockedAmount;

    event TokensLocked(address indexed beneficiary, uint256 amount, uint256 releaseTime);
    event TokensReleased(address indexed beneficiary, uint256 amount);

    /**
     * @dev Initializes the contract with the given parameters.
     * @param _tokenAddress The address of the ERC20 token.
     * @param _beneficiary The address of the beneficiary.
     * @param _lockedAmount The amount of tokens to be locked.
     * @param _releaseTime The time at which the tokens will be released.
     */
    constructor(address _tokenAddress, address _beneficiary, uint256 _lockedAmount, uint256 _releaseTime) {
        require(_releaseTime > block.timestamp, "Release time is in the past");

        token = IERC20(_tokenAddress);
        beneficiary = _beneficiary;
        lockedAmount = _lockedAmount;
        releaseTime = _releaseTime;

        emit TokensLocked(_beneficiary, _lockedAmount, _releaseTime);
    }

    /**
     * @notice Releases the locked tokens to the beneficiary.
     * @dev Only the beneficiary can call this function. Tokens can only be released after the release time.
     */
    function releaseTokens() external {
        require(block.timestamp >= releaseTime, "Current time is before release time");
        require(msg.sender == beneficiary, "Only the beneficiary can release tokens");

        uint256 amount = lockedAmount;
        lockedAmount = 0;

        require(token.transfer(beneficiary, amount), "Token transfer failed");

        emit TokensReleased(beneficiary, amount);
    }

    /**
     * @notice Returns the lock details.
     * @return The beneficiary address, locked amount, and release time.
     */
    function getLockDetails() public view returns (address, uint256, uint256) {
        return (beneficiary, lockedAmount, releaseTime);
    }
}
