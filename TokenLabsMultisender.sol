// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title TokenLabsMultisender
 * @dev This contract facilitates sending the same amount of tokens to multiple addresses in a single transaction.
 * It applies a sending fee that is transferred to the contract owner.
 */
contract TokenLabsMultisender is Ownable2Step {
  using SafeERC20 for IERC20;

  /**
   * @dev The fee amount charged for sending tokens using massSendTokens.
   */
  uint256 public feeAmount = 0.01 ether;

  /**
   * @dev Emitted when tokens are successfully sent to multiple recipients.
   * @param token The address of the ERC20 token contract.
   * @param totalAmount The total amount of tokens sent (including fees).
   * @param recipients The array of recipient addresses.
   */
  event TokensSent(address indexed token, uint256 totalAmount, address[] recipients);

  /**
   * @dev Initializes the contract ownership to the address that deployed the contract.
   */
  constructor() Ownable(msg.sender) {}

  /**
   * @notice Updates the sending fee amount. Requires the new fee amount to be greater than zero.
   * @param _newFeeAmount The new fee amount to be set.
   */
  function updateFeeAmount(uint256 _newFeeAmount) external onlyOwner {
    require(_newFeeAmount > 0, "Fee amount must be greater than 0");
    feeAmount = _newFeeAmount;
  }

  /**
   * @notice Override renounceOwnership.
   */
  function renounceOwnership() public override onlyOwner {
    revert("Renounce ownership is not allowed");
  }

  /**
   * @notice Sends tokens to multiple recipients in a single transaction.
   * @dev Utilizes the transferFrom function of ERC20 tokens to send the same amount of tokens to each specified address.
   * Additionally, it transfers a fixed fee to the contract owner.
   * @param tokenAddress The address of the ERC20 token contract.
   * @param amount The amount of tokens to send to each recipient.
   * @param recipients An array of recipient addresses.
   */
  function massSendTokens(address tokenAddress, uint256 amount, address[] calldata recipients) external payable {
    require(tokenAddress != address(0), "Invalid token address");
    require(amount > 0, "Amount must be greater than 0");
    require(recipients.length > 0, "The recipient array cannot be empty");
    
    uint256 totalFeeAmount = feeAmount * recipients.length;
    require(msg.value == totalFeeAmount, "Incorrect fee amount sent");

    (bool success, ) = owner().call{value: msg.value}("");
    require(success, "Transfer failed");

    IERC20 token = IERC20(tokenAddress);

    uint256 totalAmount = amount * recipients.length;
    require(token.balanceOf(msg.sender) >= totalAmount, "Insufficient balance");
    require(token.allowance(msg.sender, address(this)) >= totalAmount, "Insufficient allowance");

    for (uint256 i = 0; i < recipients.length; i++) {
      require(recipients[i] != address(0), "Invalid recipient address");
      token.safeTransferFrom(msg.sender, recipients[i], amount);
    }

    emit TokensSent(tokenAddress, totalAmount, recipients);
  }
}
