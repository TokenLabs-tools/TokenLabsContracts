// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title TokenLabsVesting
 * @dev This contract handles the vesting of ERC20 tokens for a single beneficiary. 
 *      Tokens are released over time according to a vesting schedule.
 */
contract TokenLabsVesting is ReentrancyGuard {
    using SafeERC20 for IERC20;
    struct VestingSchedule { uint256 totalAmount; uint256 initialRelease; uint256 amountReleased; uint256 vestingStart; uint256 vestingDuration; bool initialReleaseClaimed;}

    IERC20 public token;
    VestingSchedule public vestingSchedule;
    address public beneficiary;
    uint256 public releaseInterval;

    event TokensClaimed(address indexed beneficiary, uint256 amount);
    event VestingAdded(address indexed beneficiary, uint256 totalAmount, uint256 vestingStart, uint256 vestingDuration);

    /**
     * @dev Initializes the contract with the given parameters.
     * @param _tokenAddress The address of the ERC20 token.
     * @param _beneficiary The address of the beneficiary.
     * @param _totalAmount The total amount of tokens to be vested.
     * @param _initialRelease The amount of tokens to be released initially.
     * @param _vestingStart The start time of the vesting period.
     * @param _vestingDuration The duration of the vesting period.
     * @param _releaseInterval The interval at which tokens are released.
     */
    constructor(address _tokenAddress, address _beneficiary, uint256 _totalAmount, uint256 _initialRelease, uint256 _vestingStart, uint256 _vestingDuration, uint256 _releaseInterval) {
        require(_beneficiary != address(0), "Beneficiary cannot be the zero address");
        require(_releaseInterval <= _vestingDuration, "Release interval must be less than or equal to vesting duration");
        require(_releaseInterval > 0, "Release interval cannot be zero");
        require(_vestingDuration > 0, "Vesting duration cannot be zero");
        require(_vestingStart >= block.timestamp, "Vesting start must be in the future");

        token = IERC20(_tokenAddress);
        beneficiary = _beneficiary;
        releaseInterval = _releaseInterval;
        vestingSchedule = VestingSchedule(_totalAmount, _initialRelease, 0, _vestingStart, _vestingDuration, false);
        emit VestingAdded(beneficiary, _totalAmount, _vestingStart, _vestingDuration);
    }

    /**
     * @notice Releases vested tokens to the beneficiary.
     * @dev Only the beneficiary can call this function. Uses a non-reentrant guard.
     */
    function releaseTokens() external nonReentrant {
        require(msg.sender == beneficiary, "Only beneficiary can release tokens");
        _releaseTokens();
    }

    /**
     * @dev Internal function to handle the release of tokens according to the vesting schedule.
     */
    function _releaseTokens() internal {
        if (vestingSchedule.initialRelease > 0 && !vestingSchedule.initialReleaseClaimed && block.timestamp >= vestingSchedule.vestingStart) {
            uint256 initialRelease = vestingSchedule.initialRelease;
            vestingSchedule.initialReleaseClaimed = true;
            token.safeTransfer(beneficiary, initialRelease);
            emit TokensClaimed(beneficiary, initialRelease);
        } else {
            uint256 vestedAmount = _calculateVestedAmount(vestingSchedule);
            uint256 claimableAmount = vestedAmount - vestingSchedule.amountReleased;
            require(claimableAmount > 0, "No Tokens to release");

            vestingSchedule.amountReleased += claimableAmount;
            token.safeTransfer(beneficiary, claimableAmount);
            emit TokensClaimed(beneficiary, claimableAmount);
        }
    }

    /**
     * @dev Internal function to calculate the vested amount based on the vesting schedule.
     * @param schedule The vesting schedule.
     * @return The total vested amount.
     */
    function _calculateVestedAmount(VestingSchedule memory schedule) private view returns (uint256) {
        if (block.timestamp < schedule.vestingStart) { return 0; } 
        else if (block.timestamp >= (schedule.vestingStart + schedule.vestingDuration)) { return schedule.totalAmount - vestingSchedule.initialRelease; } 
        else {
            uint256 timeElapsed = block.timestamp - schedule.vestingStart;
            uint256 completeIntervalsElapsed = timeElapsed / releaseInterval;
            uint256 totalIntervals = schedule.vestingDuration / releaseInterval;
            uint256 amountPerInterval = (schedule.totalAmount - vestingSchedule.initialRelease) / totalIntervals;
            return amountPerInterval * completeIntervalsElapsed;
        }
    }

    /**
     * @notice Returns the vesting schedule details.
     * @return The vesting schedule.
     */
    function getVestingDetails() public view returns (VestingSchedule memory) { return vestingSchedule; }
}
