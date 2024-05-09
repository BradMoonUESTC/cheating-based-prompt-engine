// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {IETHG} from "./interfaces/IETHG.sol";
import {YieldToken} from "./YieldToken.sol";

contract ETHG is YieldToken, IETHG {
    mapping(address => bool) public vaults;

    modifier onlyVault() {
        require(vaults[msg.sender], "ETHG: forbidden");
        _;
    }

    constructor(address _vault) YieldToken("ETH Gambit", "ETHG", 0) {
        vaults[_vault] = true;
    }

    function addVault(address _vault) external override onlyOwner {
        vaults[_vault] = true;
    }

    function removeVault(address _vault) external override onlyOwner {
        vaults[_vault] = false;
    }

    function mint(
        address _account,
        uint256 _amount
    ) external override onlyVault {
        _mint(_account, _amount);
    }

    function burn(
        address _account,
        uint256 _amount
    ) external override onlyVault {
        _burn(_account, _amount);
    }
}
