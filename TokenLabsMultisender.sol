// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TokenLabsMultisender
 * @dev Este contrato permite enviar la misma cantidad de tokens a múltiples direcciones en una única transacción.
 *      Se aplica una tarifa de envío que se transfiere al propietario del contrato.
 */
contract TokenLabsMultisender is Ownable {
    using SafeERC20 for IERC20;

    uint256 public feeAmount = 0.01 ether;

    event TokensSent(address indexed token, uint256 totalAmount, address[] recipients);

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Actualiza la cantidad de la tarifa.
     * @param _newFeeAmount La nueva cantidad de la tarifa.
     */
    function updateFeeAmount(uint256 _newFeeAmount) external onlyOwner {
        require(_newFeeAmount > 0, "Fee amount must be greater than 0");
        feeAmount = _newFeeAmount;
    }

    /**
     * @notice Envía tokens a múltiples direcciones.
     * @dev Utiliza la función `transferFrom` de los tokens ERC20 para enviar la misma cantidad de tokens a cada dirección especificada.
     *      Además, transfiere una tarifa fija al propietario del contrato.
     * @param tokenAddress La dirección del contrato del token ERC20.
     * @param amount La cantidad de tokens a enviar a cada dirección.
     * @param recipients Un array de direcciones de los destinatarios.
     */
    function massSendTokens(address tokenAddress, uint256 amount, address[] calldata recipients) external payable {
        require(tokenAddress != address(0), "Invalid token address");
        require(amount > 0, "Amount must be greater than 0");
        require(recipients.length > 0, "The recipient array cannot be empty");
        require(msg.value == feeAmount, "Incorrect fee amount sent");

        IERC20 token = IERC20(tokenAddress);

        uint256 totalAmount = amount * recipients.length;
        require(token.balanceOf(msg.sender) >= totalAmount, "Insufficient balance");
        require(token.allowance(msg.sender, address(this)) >= totalAmount, "Insufficient allowance");

        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "Invalid recipient address");
            token.safeTransferFrom(msg.sender, recipients[i], amount);
        }

        payable(owner()).transfer(msg.value);

        emit TokensSent(tokenAddress, totalAmount, recipients);
    }
}
