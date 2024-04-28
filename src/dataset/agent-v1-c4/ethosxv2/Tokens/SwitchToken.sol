// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20RebaseUpgradeable} from "../Utils/ERC20RebaseUpgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

interface ISwitchToken {
    function totalSupply() external view returns (uint256);

    function runSettlement(uint256 adjustment_factor_) external;

    function mintShares(address mint_address_, uint256 mint_amount_shares_) external;

    function burn(address burn_address_, uint256 burn_amount_) external;

    function convertToShares(uint256 amount_) external returns (uint256);
}

contract SwitchToken is ERC20RebaseUpgradeable {
    event Mint(address indexed mint_address, uint256 mint_amount);
    event MintShares(address indexed mint_address, uint256 mint_amount_shares);
    event Burn(address indexed burn_address, uint256 burn_amount);

    address private _controller_address;
    address private _vault_address;
    uint8 private _decimals;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function __SwitchToken_init(string memory name_, string memory symbol_) public initializer {
        __ERC20ReBaseUpgradeable_init(name_, symbol_);
        _controller_address = msg.sender;
    }

    function setAddresses(address controller_address_, address vault_address_) external {
        require(msg.sender == _controller_address, "SwitchToken: Only controller can set addresses");

        _controller_address = controller_address_;
        _vault_address = vault_address_;

        _decimals = IERC20Metadata(controller_address_).decimals();
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function transferSharesFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        address spender = _msgSender();
        if (spender != _vault_address) {
            _spendShareAllowance(from, spender, amount);
        }
        _transferShares(from, to, amount);
        return true;
    }

    function mintShares(address mint_address_, uint256 mint_amount_shares_) external {
        require(msg.sender == _controller_address, "SwitchToken: Only controller can mint shares");
        _mintShares(mint_address_, mint_amount_shares_);
        emit MintShares(mint_address_, mint_amount_shares_);
    }

    function burn(address burn_address_, uint256 burn_amount_) external {
        require(msg.sender == _controller_address, "SwitchToken: Only controller can burn");
        _burn(burn_address_, burn_amount_);
        emit Burn(burn_address_, burn_amount_);
    }

    function runSettlement(uint256 adj_factor_) external {
        require(msg.sender == _controller_address, "SwitchToken: Only controller can run settlement");
        rebase(adj_factor_);
    }

    uint256[50] private __gap;
}
