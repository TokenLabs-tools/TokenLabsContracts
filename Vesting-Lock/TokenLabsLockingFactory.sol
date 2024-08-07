// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import "./TokenLabsVesting.sol";
import "./TokenLabsLock.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TokenLabsLockingFactory
 * @dev This contract allows the creation of vesting and lock contracts for ERC20 tokens. 
 *      It charges a fee for creating each type of contract.
 */
contract TokenLabsLockingFactory is Ownable {

    uint256 public vestingFee = 0.01 ether; // Default fee for creating a vesting contract
    uint256 public lockFee = 0.005 ether; // Default fee for creating a lock contract

    event VestingContractCreated(address indexed vestingContract, address indexed beneficiary, address indexed token, uint256 totalAmount, uint256 initialRelease, uint256 vestingStart, uint256 vestingDuration, uint256 releaseInterval);
    event LockContractCreated(address indexed lockContract, address indexed beneficiary, address indexed token, uint256 lockedAmount, uint256 releaseTime);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @notice Sets the fee for creating vesting contracts.
     * @param _vestingFee The new vesting fee.
     * @dev Only callable by the contract owner.
     */
    function setVestingFee(uint256 _vestingFee) external onlyOwner { vestingFee = _vestingFee; }

    /**
     * @notice Sets the fee for creating lock contracts.
     * @param _lockFee The new lock fee.
     * @dev Only callable by the contract owner.
     */
    function setLockFee(uint256 _lockFee) external onlyOwner { lockFee = _lockFee; }

    /**
     * @notice Creates a new vesting contract.
     * @param _tokenAddress The address of the ERC20 token.
     * @param _beneficiary The address of the beneficiary.
     * @param _totalAmount The total amount of tokens to be vested.
     * @param _initialRelease The amount of tokens to be released initially.
     * @param _vestingStart The start time of the vesting period.
     * @param _vestingDuration The duration of the vesting period.
     * @param _releaseInterval The interval at which tokens are released.
     * @return The address of the newly created vesting contract.
     * @dev Requires a fee to be paid. The fee is transferred to the contract owner.
     */
    function createVestingContract(address _tokenAddress, address _beneficiary, uint256 _totalAmount, uint256 _initialRelease, uint256 _vestingStart, uint256 _vestingDuration, uint256 _releaseInterval) external payable returns (address) {
        require(msg.value >= vestingFee, "Insufficient fee for vesting contract");
        require(_initialRelease <= _totalAmount, "Initial release amount cannot be greater than the total amount");

        (bool sent, ) = owner().call{value: msg.value}("");
        require(sent, "Transfer failed");

        TokenLabsVesting vestingContract = new TokenLabsVesting(_tokenAddress, _beneficiary, _totalAmount, _initialRelease, _vestingStart, _vestingDuration, _releaseInterval);

        address vestingContractAddress = address(vestingContract);

        emit VestingContractCreated(vestingContractAddress, _beneficiary, _tokenAddress, _totalAmount, _initialRelease, _vestingStart, _vestingDuration, _releaseInterval);

        return vestingContractAddress;
    }

    /**
     * @notice Creates a new lock contract.
     * @param _tokenAddress The address of the ERC20 token.
     * @param _beneficiary The address of the beneficiary.
     * @param _lockedAmount The amount of tokens to be locked.
     * @param _releaseTime The time at which the tokens will be released.
     * @return The address of the newly created lock contract.
     * @dev Requires a fee to be paid. The fee is transferred to the contract owner.
     */
    function createLockContract(address _tokenAddress, address _beneficiary, uint256 _lockedAmount, uint256 _releaseTime) external payable returns (address) {
        require(msg.value >= lockFee, "Insufficient fee for lock contract");
        require(_lockedAmount > 0, "Locked amount must be greater than zero");

        (bool sent, ) = owner().call{value: msg.value}("");
        require(sent, "Transfer failed");

        TokenLabsLock lockContract = new TokenLabsLock(_tokenAddress, _beneficiary, _lockedAmount, _releaseTime);

        address lockContractAddress = address(lockContract);

        emit LockContractCreated(lockContractAddress, _beneficiary, _tokenAddress, _lockedAmount, _releaseTime);

        return lockContractAddress;
    }

}
