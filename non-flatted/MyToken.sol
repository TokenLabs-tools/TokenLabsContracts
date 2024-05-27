// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "./IMyToken.sol"; // Asegúrate de que la ruta de importación es correcta

contract MyToken is ERC20, Ownable(msg.sender), ERC20Permit, IMyToken {
    bool public isBurnable;
    bool public isMintable;

    constructor(
        string memory name, 
        string memory symbol, 
        address creator,
        uint256 initialSupply,
        bool _isBurnable, 
        bool _isMintable
    ) ERC20(name, symbol) ERC20Permit(name) {
        isBurnable = _isBurnable;
        isMintable = _isMintable;
        _mint(creator, initialSupply);
        transferOwnership(msg.sender);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        require(isMintable, "Token is not mintable");
        _mint(to, amount);
    }

    function burn(uint256 amount) public {
        require(isBurnable, "Token is not burnable");
        _burn(_msgSender(), amount);
    }
}