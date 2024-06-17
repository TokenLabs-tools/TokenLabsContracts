// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import "./TokenLabsVesting.sol";
import "./TokenLabsLock.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenLabsLockingFactory is Ownable {
    address[] public vestingContracts;
    address[] public lockContracts;

    uint256 public vestingFee = 0.01 ether; // Tarifa predeterminada para crear un contrato de vesting
    uint256 public lockFee = 0.005 ether; // Tarifa predeterminada para crear un contrato de lock

    event VestingContractCreated(
        address indexed vestingContract,
        address indexed beneficiary,
        address indexed token,
        uint256 totalAmount,
        uint256 initialRelease,
        uint256 vestingStart,
        uint256 vestingDuration,
        uint256 releaseInterval
    );

    event LockContractCreated(
        address indexed lockContract,
        address indexed beneficiary,
        address indexed token,
        uint256 lockedAmount,
        uint256 releaseTime
    );

    constructor() Ownable(msg.sender) {}

    function setVestingFee(uint256 _vestingFee) external onlyOwner {
        vestingFee = _vestingFee;
    }

    function setLockFee(uint256 _lockFee) external onlyOwner {
        lockFee = _lockFee;
    }

    function createVestingContract(
        address _tokenAddress,
        address _beneficiary,
        uint256 _totalAmount,
        uint256 _initialRelease,
        uint256 _vestingStart,
        uint256 _vestingDuration,
        uint256 _releaseInterval
    ) external payable returns (address) {
        require(msg.value >= vestingFee, "Insufficient fee for vesting contract");

        TokenLabsVesting vestingContract = new TokenLabsVesting(
            _tokenAddress,
            _beneficiary,
            _totalAmount,
            _initialRelease,
            _vestingStart,
            _vestingDuration,
            _releaseInterval
        );

        address vestingContractAddress = address(vestingContract);
        vestingContracts.push(vestingContractAddress);

        payable(owner()).transfer(vestingFee);

        emit VestingContractCreated(
            vestingContractAddress,
            _beneficiary,
            _tokenAddress,
            _totalAmount,
            _initialRelease,
            _vestingStart,
            _vestingDuration,
            _releaseInterval
        );

        return vestingContractAddress;
    }

    function createLockContract(
        address _tokenAddress,
        address _beneficiary,
        uint256 _lockedAmount,
        uint256 _releaseTime
    ) external payable returns (address) {
        require(msg.value >= lockFee, "Insufficient fee for lock contract");

        TokenLabsLock lockContract = new TokenLabsLock(
            _tokenAddress,
            _beneficiary,
            _lockedAmount,
            _releaseTime
        );

        address lockContractAddress = address(lockContract);
        lockContracts.push(lockContractAddress);

        payable(owner()).transfer(lockFee);

        emit LockContractCreated(
            lockContractAddress,
            _beneficiary,
            _tokenAddress,
            _lockedAmount,
            _releaseTime
        );

        return lockContractAddress;
    }

    function getVestingContracts() external view returns (address[] memory) {
        return vestingContracts;
    }

    function getLockContracts() external view returns (address[] memory) {
        return lockContracts;
    }
}
