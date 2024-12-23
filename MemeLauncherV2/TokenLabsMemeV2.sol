// SPDX-License-Identifier: MIT
// Fork from https://bellum.exchange/

pragma solidity ^0.8.17;

import "./interfaces/ITokenLabsMemeV2.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TokenLabsMemeV2 is ERC20, ITokenLabsMemeV2 {

    // Address of TokenLabs Contracts
    address public tokenLabsFactory;

    // Bonding Curve Complete
    bool public curveComplete;

    constructor(string memory _name, string memory _symbol, uint112 _totalSupply) ERC20(_name, _symbol) {
        tokenLabsFactory = msg.sender;
        _mint(msg.sender, _totalSupply);
    }

    function completeTheCurve() external {
        require(msg.sender == tokenLabsFactory, "TokenLabs: NOT_ALLOWED");
        curveComplete = true;
    }

    function _update(address from, address to, uint256 amount) internal virtual override {
        // Is still in bonding curve phase
        super._update(from, to, amount);
        if (!curveComplete) {
            require(from == tokenLabsFactory || to == tokenLabsFactory || from == address(0), "TokenLabs: Cannot transfer tokens yet");
        }
    }
}