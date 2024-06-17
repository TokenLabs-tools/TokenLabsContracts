// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract TokenLabsVesting is ReentrancyGuard {
    using SafeERC20 for IERC20;
    struct VestingSchedule { uint256 totalAmount; uint256 initalRelease; uint256 amountReleased; uint256 vestingStart; uint256 vestingDuration; bool initialReleaseClaimed;}

    IERC20 public token;
    VestingSchedule public vestingSchedule;
    address public beneficiary;
    uint256 public releaseInterval;

    event TokensClaimed(address indexed beneficiary, uint256 amount);
    event VestingAdded(address indexed beneficiary, uint256 totalAmount, uint256 vestingStart, uint256 vestingDuration);

    constructor(address _tokenAddress, address _beneficiary, uint256 _totalAmount, uint256 _initialRelease, uint256 _vestingStart, uint256 _vestingDuration, uint256 _releaseInterval) {
        token = IERC20(_tokenAddress);
        beneficiary = _beneficiary;
        releaseInterval = _releaseInterval;
        vestingSchedule = VestingSchedule(_totalAmount, _initialRelease, 0, _vestingStart, _vestingDuration, false);
        emit VestingAdded(beneficiary, _totalAmount, _vestingStart, _vestingDuration);
    }

    function releaseTokens() external nonReentrant {
        require(msg.sender == beneficiary, "Only beneficiary can release tokens");
        _releaseTokens();
    }

    function _releaseTokens() internal {
        if (vestingSchedule.initalRelease > 0 && !vestingSchedule.initialReleaseClaimed && block.timestamp >= vestingSchedule.vestingStart) {
            uint256 initalRelease = vestingSchedule.initalRelease;
            vestingSchedule.initialReleaseClaimed = true;
            token.safeTransfer(beneficiary, initalRelease);
            emit TokensClaimed(beneficiary, initalRelease);
        } else {
            uint256 vestedAmount = _calculateVestedAmount(vestingSchedule);
            uint256 claimableAmount = vestedAmount - vestingSchedule.amountReleased;
            require(claimableAmount > 0, "No Tokens to release");

            vestingSchedule.amountReleased += claimableAmount;
            token.safeTransfer(beneficiary, claimableAmount);
            emit TokensClaimed(beneficiary, claimableAmount);
        }
    }

    function _calculateVestedAmount(VestingSchedule memory schedule) private view returns (uint256) {
        if (block.timestamp < schedule.vestingStart) { return 0; } 
        else if (block.timestamp >= (schedule.vestingStart + schedule.vestingDuration)) { return schedule.totalAmount; } 
        else {
            uint256 timeElapsed = block.timestamp - schedule.vestingStart;
            uint256 completeIntervalsElapsed = timeElapsed / releaseInterval;
            uint256 totalIntervals = schedule.vestingDuration / releaseInterval;
            uint256 amountPerInterval = schedule.totalAmount / totalIntervals;
            return amountPerInterval * completeIntervalsElapsed;
        }
    }

    function getVestingDetails() public view returns (VestingSchedule memory) { return vestingSchedule; }
}
