// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC1155SupplyUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ERC20RebaseUpgradeable} from "../Utils/ERC20RebaseUpgradeable.sol";

interface IVault {
    function totalDepositTokenAmount(uint256 vault_id_, address token_address_) external view returns (uint256);

    function mint(address mint_address_, address token_address_, address shares_address_, bool is_burn_, bool is_mint_, uint256 vault_id_, uint256 amount_) external returns (uint256);

    function burnAll(address burn_address_, uint256 vault_id_) external;

    function makeDeposit(uint256 vault_id_, address token_address_) external returns (uint256);

    function setClaimable(uint256 vault_id_, address token_address_, uint256 amount_) external;
}

// 3 slots
struct VaultConfig {
    address deposit_token_address;
    bool is_deposit_token_rebaseable;
    address claim_token_address;
    bool is_claim_token_rebaseable;
    bool processed;
    uint256 claim_token_balance;
}

contract Vault is
    ERC1155SupplyUpgradeable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable // Owner of the vault contract will be Controller
{
    using SafeERC20 for IERC20;

    mapping(uint256 => VaultConfig) private _vault_configs;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function __Vault_init() public initializer {
        __ERC1155_init("");
        __Ownable_init(msg.sender);
    }

    function depositToken(uint256 vault_id_) public view returns (address) {
        return _vault_configs[vault_id_].deposit_token_address;
    }

    function claimToken(uint256 vault_id_) public view returns (address) {
        return _vault_configs[vault_id_].claim_token_address;
    }

    function totalDepositTokenAmount(uint256 vault_id_, address deposit_token_address_) public view returns (uint256) {
        if (_vault_configs[vault_id_].processed) return 0;

        uint256 vault_balance_deposit_token_ = totalSupply(vault_id_);

        return _vault_configs[vault_id_].is_deposit_token_rebaseable ? ERC20RebaseUpgradeable(deposit_token_address_).convertToAmount(vault_balance_deposit_token_) : vault_balance_deposit_token_;
    }

    function totalClaimTokenAmount(uint256 vault_id_) public view returns (uint256) {
        uint256 vault_balance_claim_token_ = _vault_configs[vault_id_].claim_token_balance;

        return _vault_configs[vault_id_].is_claim_token_rebaseable ? ERC20RebaseUpgradeable(_vault_configs[vault_id_].claim_token_address).convertToAmount(vault_balance_claim_token_) : vault_balance_claim_token_;
    }

    function batchBalanceOfDepositTokens(address account_address_, uint256[] calldata vault_ids_) external view returns (uint256[] memory deposit_token_balances_) {
        deposit_token_balances_ = new uint256[](vault_ids_.length);
        for (uint256 i = 0; i < vault_ids_.length; ++i) {
            if (_vault_configs[vault_ids_[i]].processed) continue;

            uint256 account_balance_vault_token_ = balanceOf(account_address_, vault_ids_[i]);

            if (account_balance_vault_token_ == 0) continue;

            deposit_token_balances_[i] = _vault_configs[vault_ids_[i]].is_deposit_token_rebaseable ? ERC20RebaseUpgradeable(_vault_configs[vault_ids_[i]].deposit_token_address).convertToAmount(account_balance_vault_token_) : account_balance_vault_token_;
        }
    }

    function batchBalanceOfClaimTokens(address account_address_, uint256[] calldata vault_ids_) external view returns (uint256[] memory claim_token_balances_) {
        claim_token_balances_ = new uint256[](vault_ids_.length);
        for (uint256 i = 0; i < vault_ids_.length; ++i) {
            if (!_vault_configs[vault_ids_[i]].processed) continue;

            uint256 account_balance_vault_token_ = balanceOf(account_address_, vault_ids_[i]);

            if (account_balance_vault_token_ == 0) continue;

            uint256 account_share_balance_claim_token_ = (account_balance_vault_token_ * _vault_configs[vault_ids_[i]].claim_token_balance) / totalSupply(vault_ids_[i]); // claim token shares

            claim_token_balances_[i] = _vault_configs[vault_ids_[i]].is_claim_token_rebaseable ? ERC20RebaseUpgradeable(_vault_configs[vault_ids_[i]].claim_token_address).convertToAmount(account_share_balance_claim_token_) : account_share_balance_claim_token_;
        }
    }

    function mint(address mint_address_, address deposit_token_address_, address claim_token_address_, bool is_deposit_token_rebaseable_, bool is_claim_token_rebaseable_, uint256 vault_id_, uint256 deposit_amount_) external onlyOwner returns (uint256 vault_token_amount_) {
        if (totalSupply(vault_id_) == 0) {
            _vault_configs[vault_id_].deposit_token_address = deposit_token_address_;
            _vault_configs[vault_id_].claim_token_address = claim_token_address_;
            _vault_configs[vault_id_].is_deposit_token_rebaseable = is_deposit_token_rebaseable_;
            _vault_configs[vault_id_].is_claim_token_rebaseable = is_claim_token_rebaseable_;
        }

        if (is_deposit_token_rebaseable_) {
            // convert the deposit amount to shares first
            vault_token_amount_ = ERC20RebaseUpgradeable(deposit_token_address_).convertToShares(deposit_amount_);

            require(ERC20RebaseUpgradeable(deposit_token_address_).transferSharesFrom(mint_address_, address(this), vault_token_amount_), "ERC20Rebaseable: TransferFrom Failed");
        } else {
            vault_token_amount_ = deposit_amount_;
            IERC20(deposit_token_address_).safeTransferFrom(mint_address_, address(this), vault_token_amount_);
        }

        _mint(mint_address_, vault_id_, vault_token_amount_, "");
    }

    function burnAll(address burn_address_, uint256 vault_id_) external onlyOwner {
        VaultConfig memory vault_config_ = _vault_configs[vault_id_];

        require(!vault_config_.processed, "Cannot cancel processed orders");

        uint256 burn_amount_ = balanceOf(burn_address_, vault_id_);
        if (burn_amount_ == 0) return;

        _burn(burn_address_, vault_id_, burn_amount_);

        if (vault_config_.is_deposit_token_rebaseable) {
            require(ERC20RebaseUpgradeable(vault_config_.deposit_token_address).transferShares(burn_address_, burn_amount_), "ERC20Rebaseable: Transfer Failed");
        } else {
            IERC20(vault_config_.deposit_token_address).safeTransfer(burn_address_, burn_amount_);
        }
    }

    /*
        Here we have to ensure that the claimable amount passed is in terms of shares if the claim token is rebaseable
    */

    function setClaimable(uint256 vault_id_, address claim_token_address_, uint256 claimable_amount_) external onlyOwner {
        unchecked {
            _vault_configs[vault_id_].claim_token_balance = claimable_amount_;
        }
        _vault_configs[vault_id_].processed = true;
    }

    function makeDeposit(uint256 vault_id_, address deposit_token_address_) external onlyOwner returns (uint256 deposit_amount_) {
        deposit_amount_ = totalSupply(vault_id_);

        if (deposit_amount_ == 0) {
            return 0;
        }

        if (_vault_configs[vault_id_].is_deposit_token_rebaseable) {
            require(ERC20RebaseUpgradeable(deposit_token_address_).transferShares(msg.sender, deposit_amount_), "ERC20Rebaseable: Transfer Failed");

            deposit_amount_ = ERC20RebaseUpgradeable(deposit_token_address_).convertToAmount(deposit_amount_);
        } else {
            IERC20(deposit_token_address_).safeTransfer(msg.sender, deposit_amount_);
        }
    }

    function _claimInfo(uint256 vault_id_, uint256 claim_amount_) private view returns (address claim_token_address_, uint256 vault_balance_claim_token_, uint256 amount_to_transfer_claim_token_, bool is_claim_token_rebaseable_) {
        if (!_vault_configs[vault_id_].processed) return (claim_token_address_, vault_balance_claim_token_, amount_to_transfer_claim_token_, is_claim_token_rebaseable_);

        claim_token_address_ = _vault_configs[vault_id_].claim_token_address;

        is_claim_token_rebaseable_ = _vault_configs[vault_id_].is_claim_token_rebaseable;

        vault_balance_claim_token_ = _vault_configs[vault_id_].claim_token_balance;

        require(vault_balance_claim_token_ > 0, "Vault: no claim");

        unchecked {
            amount_to_transfer_claim_token_ = (claim_amount_ * vault_balance_claim_token_) / totalSupply(vault_id_); // claim shares to burn
        }
    }

    function claimAmount(uint256 vault_id_, uint256 claim_amount_) external view returns (uint256 amount_to_transfer_claim_token_) {
        (, , amount_to_transfer_claim_token_, ) = _claimInfo(vault_id_, claim_amount_);
    }

    function claim(uint256 vault_id_, uint256 claim_amount_) external nonReentrant {
        (address claim_token_address_, uint256 vault_balance_claim_token_, uint256 amount_to_transfer_claim_token_, bool is_claim_token_rebaseable_) = _claimInfo(vault_id_, claim_amount_);

        _burn(_msgSender(), vault_id_, claim_amount_);

        unchecked {
            _vault_configs[vault_id_].claim_token_balance = vault_balance_claim_token_ - amount_to_transfer_claim_token_;
        }

        if (is_claim_token_rebaseable_) {
            require(ERC20RebaseUpgradeable(claim_token_address_).transferShares(_msgSender(), amount_to_transfer_claim_token_), "ERC20Rebaseable: Transfer Failed");
        } else {
            IERC20(claim_token_address_).safeTransfer(_msgSender(), amount_to_transfer_claim_token_);
        }
    }

    uint256[50] private __gap;
}
