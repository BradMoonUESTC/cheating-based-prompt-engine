// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import {INToken} from "./interfaces/INToken.sol";

contract NToken is
    Initializable,
    INToken,
    ERC20Upgradeable,
    OwnableUpgradeable
{
    address internal underlyingAsset;

    mapping(address => bool) private authorized;

    modifier onlyAuthorized() {
        require(authorized[msg.sender], "nToken: caller is not authorized");
        _;
    }

    function initialize(
        string calldata _name,
        string calldata _symbol,
        address _underlyingAsset
    ) external override initializer {
        __Ownable_init();
        __ERC20_init(_name, _symbol);

        underlyingAsset = _underlyingAsset;
    }

    function authorise(address _addr, bool _authorized) external onlyOwner {
        authorized[_addr] = _authorized;
    }

    function mint(
        address account,
        uint256 amount
    ) external override onlyAuthorized {
        _mint(account, amount);
    }

    function burn(
        address account,
        uint256 amount
    ) external override onlyAuthorized {
        _burn(account, amount);
    }

    function UNDERLYING_ASSET_ADDRESS() public view override returns (address) {
        return underlyingAsset;
    }
}
