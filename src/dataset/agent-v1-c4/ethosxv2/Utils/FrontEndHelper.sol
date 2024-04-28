// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SwitchToken} from "../Tokens/SwitchToken.sol";
import {Vault} from "../Tokens/Vault.sol";
import {SettlementManager} from "../Utils/SettlementManager.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {SellerConstantDeltaController} from "../Controller/SellerConstantDeltaController.sol";
import {ControllerBase, FeesParams} from "../Controller/ControllerBase.sol";
import {ProxyUSDC} from "../Tokens/ProxyUSDC.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

struct CycleData {
  uint256 cycle_start_time;
  uint256 cycle_end_time;
}

struct Addresses {
  address settlement_token_address;
  address vault_address;
  address long_token_address;
  address short_token_address;
  address controller_address;
  address settlement_manager_address;
}

struct VaultDeposits {
  uint256 long_deposit_amount;
  uint256 long_withdraw_amount;
  uint256 short_deposit_amount;
  uint256 short_withdraw_amount;
  uint256 long_switch_amount;
  uint256 short_switch_amount;
}

struct AllContractsInfo {
  VaultDeposits vault_deposits;
  uint256 long_token_supply;
  uint256 short_token_supply;
  int8 opt_type;
  FeesParams fees_params;
  uint256 settlement_count;
  uint256 pending_settlement_count;
  CycleData cycle_data;
  uint256 latest_settlement_price;
  uint256 latest_settlement_time;
}

struct BalanceInfo {
  uint256 native_token_balance;
  uint256 settlement_token_balance;
  uint256 long_token_balance;
  uint256 short_token_balance;
}

contract FrontEndHelper is OwnableUpgradeable {
  mapping(string => mapping(string => Addresses)) private addresses_map;

  function __FrontEndHelper_init() public initializer {
    __Ownable_init(msg.sender);
  }

  function setAddresses(Addresses calldata addresses, string memory token, string memory option_type) public onlyOwner {
    addresses_map[token][option_type] = addresses;
  }

  function getAddresses(string memory token, string memory option_type) public view returns (Addresses memory) {
    return addresses_map[token][option_type];
  }

  function getAllContractsInfo(string memory token, string memory option_type) public view returns (AllContractsInfo memory info) {
    Addresses memory contract_addresses = addresses_map[token][option_type];

    //Controller Params
    FeesParams memory fees_params;
    int8 opt_type = ControllerBase(contract_addresses.controller_address).optType();
    {
      (uint256 loading_fees_long, uint256 unloading_fees_long, uint256 switching_fees_long, uint256 settlement_fees_long, uint256 loading_fees_short, uint256 unloading_fees_short, uint256 switching_fees_short, uint256 settlement_fees_short) = ControllerBase(contract_addresses.controller_address).fees_params();
      fees_params = FeesParams(loading_fees_long, unloading_fees_long, switching_fees_long, settlement_fees_long, loading_fees_short, unloading_fees_short, switching_fees_short, settlement_fees_short);
    }

    //Settlement Manager info
    uint256 cycle_start_time = SettlementManager(contract_addresses.settlement_manager_address).lastSettlementTime();
    CycleData memory cycle_data = CycleData(cycle_start_time, cycle_start_time + SettlementManager(contract_addresses.settlement_manager_address).cycle_duration());

    //Vault Deposits
    VaultDeposits memory vault_deposits;
    {
      uint256 vault_id;
      vault_id = uint256(keccak256(abi.encodePacked("LONG_TOKEN_DEPOSIT", cycle_data.cycle_start_time)));
      uint256 long_deposit_amount = Vault(contract_addresses.vault_address).totalDepositTokenAmount(vault_id, contract_addresses.long_token_address);
      vault_id = uint256(keccak256(abi.encodePacked("LONG_TOKEN_WITHDRAW", cycle_data.cycle_start_time)));
      uint256 long_withdraw_amount = Vault(contract_addresses.vault_address).totalDepositTokenAmount(vault_id, contract_addresses.long_token_address);

      vault_id = uint256(keccak256(abi.encodePacked("SHORT_TOKEN_DEPOSIT", cycle_data.cycle_start_time)));
      uint256 short_deposit_amount = Vault(contract_addresses.vault_address).totalDepositTokenAmount(vault_id, contract_addresses.short_token_address);
      vault_id = uint256(keccak256(abi.encodePacked("SHORT_TOKEN_WITHDRAW", cycle_data.cycle_start_time)));
      uint256 short_withdraw_amount = Vault(contract_addresses.vault_address).totalDepositTokenAmount(vault_id, contract_addresses.short_token_address);

      vault_id = uint256(keccak256(abi.encodePacked("LONG_TOKEN_SWITCH", cycle_data.cycle_start_time)));
      uint256 long_switch_amount = Vault(contract_addresses.vault_address).totalDepositTokenAmount(vault_id, contract_addresses.long_token_address);
      vault_id = uint256(keccak256(abi.encodePacked("SHORT_TOKEN_SWITCH", cycle_data.cycle_start_time)));
      uint256 short_switch_amount = Vault(contract_addresses.vault_address).totalDepositTokenAmount(vault_id, contract_addresses.short_token_address);
      vault_deposits = VaultDeposits(long_deposit_amount, long_withdraw_amount, short_deposit_amount, short_withdraw_amount, long_switch_amount, short_switch_amount);
    }

    //Latest Settlement
    uint256 latest_settlement_price = SettlementManager(contract_addresses.settlement_manager_address).lastSettlementPrice();
    uint256 latest_settlement_time = SettlementManager(contract_addresses.settlement_manager_address).latestCycleStartTime();

    //Existing Supply
    uint256 long_token_supply = SwitchToken(contract_addresses.long_token_address).totalSupply();
    uint256 short_token_supply = SwitchToken(contract_addresses.short_token_address).totalSupply();

    info = AllContractsInfo(vault_deposits, long_token_supply, short_token_supply, opt_type, fees_params, 0, 0, cycle_data, latest_settlement_price, latest_settlement_time);
  }

  function getAllBalances(address user_address, string memory token, string memory option_type) public view returns (BalanceInfo memory all_balances) {
    Addresses memory contract_addresses = addresses_map[token][option_type];
    uint256 native_token_balance = user_address.balance;
    uint256 settlement_token_balance = IERC20(contract_addresses.settlement_token_address).balanceOf(user_address);
    uint256 long_token_balance = SwitchToken(contract_addresses.long_token_address).balanceOf(user_address);
    uint256 short_token_balance = SwitchToken(contract_addresses.short_token_address).balanceOf(user_address);
    all_balances = BalanceInfo(native_token_balance, settlement_token_balance, long_token_balance, short_token_balance);
  }
  uint256[50] private __gap;
}
