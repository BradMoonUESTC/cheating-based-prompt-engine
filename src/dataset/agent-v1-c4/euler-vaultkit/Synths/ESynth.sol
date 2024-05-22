// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {EnumerableSet} from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import {IEVC, EVCUtil} from "ethereum-vault-connector/utils/EVCUtil.sol";
import {ERC20Collateral, ERC20, Context} from "./ERC20Collateral.sol";
import {IEVault} from "../EVault/IEVault.sol";

/// @title ESynth
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice ESynth is an ERC20-compatible token with the EVC support which, thanks to relying on the EVC authentication
/// and requesting the account status checks on token transfers and burns, allows it to be used as collateral in other
/// vault. It is meant to be used as an underlying asset of the synthetic asset vault.
contract ESynth is ERC20Collateral, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    struct MinterData {
        uint128 capacity;
        uint128 minted;
    }

    mapping(address => MinterData) public minters;
    EnumerableSet.AddressSet internal ignoredForTotalSupply;

    event MinterCapacitySet(address indexed minter, uint256 capacity);

    error E_CapacityReached();
    error E_NotEVCCompatible();

    constructor(IEVC evc_, string memory name_, string memory symbol_)
        ERC20Collateral(evc_, name_, symbol_)
        Ownable(msg.sender)
    {}

    /// @notice Sets the minting capacity for a minter.
    /// @dev Can only be called by the owner of the contract.
    /// @param minter The address of the minter to set the capacity for.
    /// @param capacity The capacity to set for the minter.
    function setCapacity(address minter, uint128 capacity) external onlyOwner {
        minters[minter].capacity = capacity;
        emit MinterCapacitySet(minter, capacity);
    }

    /// @notice Mints a certain amount of tokens to the account.
    /// @param account The account to mint the tokens to.
    /// @param amount The amount of tokens to mint.
    function mint(address account, uint256 amount) external nonReentrant {
        address sender = _msgSender();
        MinterData memory minterCache = minters[sender];

        // Return early if the amount is 0 to prevent emitting possible spam events.
        if (amount == 0) {
            return;
        }

        if (
            amount > type(uint128).max - minterCache.minted
                || minterCache.capacity < uint256(minterCache.minted) + amount
        ) {
            revert E_CapacityReached();
        }

        minterCache.minted += uint128(amount); // safe to down-cast because amount <= capacity <= max uint128
        minters[sender] = minterCache;

        _mint(account, amount);
    }

    /// @notice Burns a certain amount of tokens from the accounts balance. Requires the account, except the owner to
    /// have an allowance for the sender.
    /// @param burnFrom The account to burn the tokens from.
    /// @param amount The amount of tokens to burn.
    function burn(address burnFrom, uint256 amount) external nonReentrant {
        address sender = _msgSender();
        MinterData memory minterCache = minters[sender];

        if (amount == 0) {
            return;
        }

        // The allowance check should be performed if the spender is not the account with the exception of the owner
        // burning from this contract.
        if (burnFrom != sender && !(burnFrom == address(this) && sender == owner())) {
            _spendAllowance(burnFrom, sender, amount);
        }

        // If burning more than minted, reset minted to 0
        unchecked {
            // down-casting is safe because amount < minted <= max uint128
            minterCache.minted = minterCache.minted > amount ? minterCache.minted - uint128(amount) : 0;
        }
        minters[sender] = minterCache;

        _burn(burnFrom, amount);
    }

    /// @notice Deposit cash from this contract into the attached vault.
    /// @dev Adds the vault to the list of accounts to ignore for the total supply.
    /// @param vault The vault to deposit the cash in.
    /// @param amount The amount of cash to deposit.
    function allocate(address vault, uint256 amount) external onlyOwner {
        if (IEVault(vault).EVC() != address(evc)) {
            revert E_NotEVCCompatible();
        }
        ignoredForTotalSupply.add(vault);
        _approve(address(this), vault, amount, true);
        IEVault(vault).deposit(amount, address(this));
    }

    /// @notice Withdraw cash from the attached vault to this contract.
    /// @param vault The vault to withdraw the cash from.
    /// @param amount The amount of cash to withdraw.
    function deallocate(address vault, uint256 amount) external onlyOwner {
        IEVault(vault).withdraw(amount, address(this), address(this));
    }

    /// @notice Retrieves the message sender in the context of the EVC.
    /// @dev Overriden due to the conflict with the Context definition.
    /// @dev This function returns the account on behalf of which the current operation is being performed, which is
    /// either msg.sender or the account authenticated by the EVC.
    /// @return The address of the message sender.
    function _msgSender() internal view virtual override (ERC20Collateral, Context) returns (address) {
        return ERC20Collateral._msgSender();
    }

    // -------- TotalSupply Management --------

    /// @notice Adds an account to the list of accounts to ignore for the total supply.
    /// @param account The account to add to the list.
    /// @return success True when the account was not on the list and was added. False otherwise.
    function addIgnoredForTotalSupply(address account) external onlyOwner returns (bool success) {
        return ignoredForTotalSupply.add(account);
    }

    /// @notice Removes an account from the list of accounts to ignore for the total supply.
    /// @param account The account to remove from the list.
    /// @return success True when the account was on the list and was removed. False otherwise.
    function removeIgnoredForTotalSupply(address account) external onlyOwner returns (bool success) {
        return ignoredForTotalSupply.remove(account);
    }

    /// @notice Checks if an account is ignored for the total supply.
    /// @param account The account to check.
    function isIgnoredForTotalSupply(address account) public view returns (bool) {
        return ignoredForTotalSupply.contains(account);
    }

    /// @notice Retrieves all the accounts ignored for the total supply.
    /// @return The list of accounts ignored for the total supply.
    function getAllIgnoredForTotalSupply() public view returns (address[] memory) {
        return ignoredForTotalSupply.values();
    }

    /// @notice Retrieves the total supply of the token.
    /// @dev Overriden to exclude the ignored accounts from the total supply.
    /// @return The total supply of the token.
    function totalSupply() public view override returns (uint256) {
        uint256 total = super.totalSupply();

        uint256 ignoredLength = ignoredForTotalSupply.length(); // cache for efficiency
        for (uint256 i = 0; i < ignoredLength; i++) {
            total -= balanceOf(ignoredForTotalSupply.at(i));
        }
        return total;
    }
}
