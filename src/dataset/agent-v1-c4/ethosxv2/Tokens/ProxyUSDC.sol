// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ProxyUSDC is ERC20, Ownable {
    uint8 private _decimals;

    event Mint(address indexed sender, uint256 amount);
    event Burn(address indexed burner, uint256 amount);

    uint256 public constant MINT_PER_ETH = 1000000000;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) Ownable(msg.sender) {
        _decimals = decimals_;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function selfDestruct() public onlyOwner {
        selfdestruct(payable(owner()));
    }

    function withdrawFunds() public onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function mint() public payable {
        uint256 mint_amount_ = msg.value * MINT_PER_ETH;
        _mint(msg.sender, mint_amount_);
        emit Mint(msg.sender, mint_amount_);
    }

    function burn(uint256 burn_amount_) public {
        _burn(msg.sender, burn_amount_);
        (bool success_, ) = address(msg.sender).call{value: burn_amount_ / MINT_PER_ETH}("");
        require(success_, "Redemption failed");
        emit Burn(msg.sender, burn_amount_);
    }
}
