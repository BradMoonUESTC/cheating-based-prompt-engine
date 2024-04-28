// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ISwitchToken} from "../Tokens/SwitchToken.sol";
import {IVault} from "../Tokens/Vault.sol";
import {ISettlementManager} from "../Utils/SettlementManager.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

struct FeesParams {
    uint256 loading_fees_long;
    uint256 unloading_fees_long;
    uint256 switching_fees_long;
    uint256 settlement_fees_long;
    uint256 loading_fees_short;
    uint256 unloading_fees_short;
    uint256 switching_fees_short;
    uint256 settlement_fees_short;
}

abstract contract ControllerBase is ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    // Events
    event BuyLongTokenDone(address indexed buyer_address, uint256 buy_amount_usdc);
    event BuyShortTokenDone(address indexed buyer_address, uint256 buy_amount_usdc);
    event SellLongTokenDone(address indexed seller_address, uint256 sell_amount_token);
    event SellShortTokenDone(address indexed seller_address, uint256 sell_amount_token);
    event SwitchFromLongToShortDone(address indexed switcher_address, uint256 switch_amount_token);
    event SwitchFromShortToLongDone(address indexed switcher_address, uint256 switch_amount_token);
    event CancelOrderDone(address indexed address_, uint256 vault_id_);
    event SettlementDone(uint256 long_token_balance_before, uint256 short_token_balance_before, uint256 long_token_balance_after, uint256 short_token_balance_after);

    bytes internal constant _LONG_TOKEN_DEPOSIT = "LONG_TOKEN_DEPOSIT";
    bytes internal constant _SHORT_TOKEN_DEPOSIT = "SHORT_TOKEN_DEPOSIT";
    bytes internal constant _LONG_TOKEN_WITHDRAWAL = "LONG_TOKEN_WITHDRAWAL";
    bytes internal constant _SHORT_TOKEN_WITHDRAWAL = "SHORT_TOKEN_WITHDRAWAL";
    bytes internal constant _LONG_TOKEN_SWITCH = "LONG_TOKEN_SWITCH";
    bytes internal constant _SHORT_TOKEN_SWITCH = "SHORT_TOKEN_SWITCH";

    uint256 internal _cycle_premium; //2%
    uint256 internal _payoff_cap;

    int8 private _opt_type;

    uint256 private _prev_settlement_price;
    uint256 private _prev_settlement_time;

    IERC20 internal _settlement_token;
    ISwitchToken internal _long_token;
    ISwitchToken internal _short_token;

    ISettlementManager internal _settlement_manager;
    IVault internal _vault;

    FeesParams public fees_params;

    address private _fee_collector;

    function __ControllerBase_init(int8 opt_type_, uint256 cycle_premium_, uint256 payoff_cap_, address long_token_address_, address short_token_address_, address settlement_token_address_) public onlyInitializing {
        __Ownable_init(msg.sender);
        _cycle_premium = cycle_premium_;
        _payoff_cap = payoff_cap_;
        _opt_type = opt_type_;
        _long_token = ISwitchToken(long_token_address_);
        _short_token = ISwitchToken(short_token_address_);
        _settlement_token = IERC20(settlement_token_address_);
    }

    function optType() public view returns (int8) {
        return _opt_type;
    }

    function payoffCap() public view returns (uint256) {
        return _payoff_cap;
    }

    function pricePerToken() public view virtual returns (uint256);

    function lastSettlementPricePerToken() public view virtual returns (uint256);

    function getLongTokenAddress() external view returns (address) {
        return address(_long_token);
    }

    function getShortTokenAddress() external view returns (address) {
        return address(_short_token);
    }

    function getVaultAddress() external view returns (address) {
        return address(_vault);
    }

    function getSettlementTokenAddress() external view returns (address) {
        return address(_settlement_token);
    }

    function cyclePremium() public view virtual returns (uint256) {
        return _cycle_premium;
    }

    function calcX(int256 pct_price_change_) internal view virtual returns (uint256 x_);

    function longTokenAdjustmentFactor(uint256 short_token_ratio_, uint256 m_, uint256 x_, uint256 fees_pct_) internal pure virtual returns (uint256 adjustment_factor_);

    function shortTokenAdjustmentFactor(uint256 short_token_ratio_, uint256 m_, uint256 x_, uint256 fees_pct_) internal pure virtual returns (uint256 adjustment_factor_);

    // =============== Admin block =================
    function setCyclePremium(uint256 cycle_premium_) public onlyOwner {
        _cycle_premium = cycle_premium_;
    }

    function setFeesParams(uint256 loading_fees_long_, uint256 unloading_fees_long_, uint256 switching_fees_long_, uint256 settlement_fees_long_, uint256 loading_fees_short_, uint256 unloading_fees_short_, uint256 switching_fees_short_, uint256 settlement_fees_short_) public onlyOwner {
        fees_params.loading_fees_long = loading_fees_long_;
        fees_params.unloading_fees_long = unloading_fees_long_;
        fees_params.switching_fees_long = switching_fees_long_;
        fees_params.settlement_fees_long = settlement_fees_long_;
        fees_params.loading_fees_short = loading_fees_short_;
        fees_params.unloading_fees_short = unloading_fees_short_;
        fees_params.switching_fees_short = switching_fees_short_;
        fees_params.settlement_fees_short = settlement_fees_short_;
    }

    function setFeeCollector(address fee_collector_) public onlyOwner {
        _fee_collector = fee_collector_;
    }

    function setSettlementTokenAddress(address settlement_token_) public onlyOwner {
        _settlement_token = IERC20(settlement_token_);
    }

    function setSwitchTokenAddresses(address long_token_, address short_token_) public onlyOwner {
        _long_token = ISwitchToken(long_token_);
        _short_token = ISwitchToken(short_token_);
    }

    function setVaultAddress(address vault_) public onlyOwner {
        _vault = IVault(vault_);
    }

    function setSettlementManagerAddress(address settlement_manager_) public onlyOwner {
        _settlement_manager = ISettlementManager(settlement_manager_);
    }

    function setPayoffCap(uint256 payoff_cap_) external onlyOwner {
        _payoff_cap = payoff_cap_;
    }

    // ==============================================
    function decimals() external view returns (uint8) {
        return IERC20Metadata(address(_settlement_token)).decimals();
    }

    function longTokenBuyAmount() public returns (uint256) {
        return _vault.totalDepositTokenAmount(uint256(keccak256(abi.encodePacked(_LONG_TOKEN_DEPOSIT, _settlement_manager.latestCycleStartTime()))), address(_settlement_token));
    }

    function shortTokenBuyAmount() public returns (uint256) {
        return _vault.totalDepositTokenAmount(uint256(keccak256(abi.encodePacked(_SHORT_TOKEN_DEPOSIT, _settlement_manager.latestCycleStartTime()))), address(_settlement_token));
    }

    function longTokenSellAmount() public returns (uint256) {
        return _vault.totalDepositTokenAmount(uint256(keccak256(abi.encodePacked(_LONG_TOKEN_WITHDRAWAL, _settlement_manager.latestCycleStartTime()))), address(_long_token));
    }

    function shortTokenSellAmount() public returns (uint256) {
        return _vault.totalDepositTokenAmount(uint256(keccak256(abi.encodePacked(_SHORT_TOKEN_WITHDRAWAL, _settlement_manager.latestCycleStartTime()))), address(_short_token));
    }

    function longTokenSwitchAmount() public returns (uint256) {
        return _vault.totalDepositTokenAmount(uint256(keccak256(abi.encodePacked(_LONG_TOKEN_SWITCH, _settlement_manager.latestCycleStartTime()))), address(_long_token));
    }

    function shortTokenSwitchAmount() public returns (uint256) {
        return _vault.totalDepositTokenAmount(uint256(keccak256(abi.encodePacked(_SHORT_TOKEN_SWITCH, _settlement_manager.latestCycleStartTime()))), address(_short_token));
    }

    function totalLongTokenSupply() public view returns (uint256) {
        return _long_token.totalSupply();
    }

    function totalShortTokenSupply() public view returns (uint256) {
        return _short_token.totalSupply();
    }

    function prevSettlementPrice() public view returns (uint256) {
        return _prev_settlement_price;
    }

    function prevSettlementTime() public view returns (uint256) {
        return _prev_settlement_time;
    }

    function getTotalCollateralValue() public view returns (uint256) {
        return _settlement_token.balanceOf(address(this));
    }

    function buyLongToken(uint256 buy_amount_usdc_) external nonReentrant returns (uint256 vault_id_, uint256 vault_token_amount_) {
        IERC20 settlement_token_ = _settlement_token;
        address msg_sender_ = _msgSender();

        require(settlement_token_.balanceOf(msg_sender_) >= buy_amount_usdc_, "Not enough balance");
        require(settlement_token_.allowance(msg_sender_, address(_vault)) >= buy_amount_usdc_, "Not enough allowance");

        vault_id_ = uint256(keccak256(abi.encodePacked(_LONG_TOKEN_DEPOSIT, _settlement_manager.latestCycleStartTime())));

        vault_token_amount_ = _vault.mint(msg_sender_, address(settlement_token_), address(_long_token), false, true, vault_id_, buy_amount_usdc_);

        emit BuyLongTokenDone(msg_sender_, buy_amount_usdc_);
    }

    function buyShortToken(uint256 buy_amount_usdc_) external nonReentrant returns (uint256 vault_id_, uint256 vault_token_amount_) {
        IERC20 settlement_token_ = _settlement_token;
        address msg_sender_ = _msgSender();

        require(settlement_token_.balanceOf(msg_sender_) >= buy_amount_usdc_, "Not enough balance");
        require(settlement_token_.allowance(msg_sender_, address(_vault)) >= buy_amount_usdc_, "Not enough allowance");

        vault_id_ = uint256(keccak256(abi.encodePacked(_SHORT_TOKEN_DEPOSIT, _settlement_manager.latestCycleStartTime())));

        vault_token_amount_ = _vault.mint(msg_sender_, address(settlement_token_), address(_short_token), false, true, vault_id_, buy_amount_usdc_);

        emit BuyShortTokenDone(msg_sender_, buy_amount_usdc_);
    }

    function sellLongToken(uint256 sell_amount_token_) external nonReentrant returns (uint256 vault_id_, uint256 vault_token_amount_) {
        IERC20 long_token_ = IERC20(address(_long_token));
        address msg_sender_ = _msgSender();

        require(long_token_.balanceOf(msg_sender_) >= sell_amount_token_, "Not enough balance");

        vault_id_ = uint256(keccak256(abi.encodePacked(_LONG_TOKEN_WITHDRAWAL, _settlement_manager.latestCycleStartTime())));

        vault_token_amount_ = _vault.mint(msg_sender_, address(long_token_), address(_settlement_token), true, false, vault_id_, sell_amount_token_);

        emit SellLongTokenDone(msg_sender_, sell_amount_token_);
    }

    function sellShortToken(uint256 sell_amount_token_) external nonReentrant returns (uint256 vault_id_, uint256 vault_token_amount_) {
        IERC20 short_token_ = IERC20(address(_short_token));
        address msg_sender_ = _msgSender();

        require(short_token_.balanceOf(msg_sender_) >= sell_amount_token_, "Not enough balance");

        vault_id_ = uint256(keccak256(abi.encodePacked(_SHORT_TOKEN_WITHDRAWAL, _settlement_manager.latestCycleStartTime())));

        vault_token_amount_ = _vault.mint(msg_sender_, address(short_token_), address(_settlement_token), true, false, vault_id_, sell_amount_token_);

        emit SellShortTokenDone(msg_sender_, sell_amount_token_);
    }

    function switchFromLongToShort(uint256 switch_amount_) external nonReentrant returns (uint256 vault_id_, uint256 vault_token_amount_) {
        IERC20 long_token_ = IERC20(address(_long_token));
        address msg_sender_ = _msgSender();

        require(long_token_.balanceOf(msg_sender_) >= switch_amount_, "Not enough balance");

        vault_id_ = uint256(keccak256(abi.encodePacked(_LONG_TOKEN_SWITCH, _settlement_manager.latestCycleStartTime())));

        vault_token_amount_ = _vault.mint(msg_sender_, address(long_token_), address(_short_token), true, true, vault_id_, switch_amount_);

        emit SwitchFromLongToShortDone(msg_sender_, switch_amount_);
    }

    function switchFromShortToLong(uint256 switch_amount_) external nonReentrant returns (uint256 vault_id_, uint256 vault_token_amount_) {
        IERC20 short_token_ = IERC20(address(_short_token));
        address msg_sender_ = _msgSender();

        require(short_token_.balanceOf(msg_sender_) >= switch_amount_, "Not enough balance");

        vault_id_ = uint256(keccak256(abi.encodePacked(_SHORT_TOKEN_SWITCH, _settlement_manager.latestCycleStartTime())));

        vault_token_amount_ = _vault.mint(msg_sender_, address(short_token_), address(_long_token), true, true, vault_id_, switch_amount_);

        emit SwitchFromShortToLongDone(msg_sender_, switch_amount_);
    }

    function cancelOrder(uint256 vault_id_) external {
        require(block.timestamp > _settlement_manager.cycleScrappingTime(), "Cycle not scrapped");
        _vault.burnAll(_msgSender(), vault_id_);

        emit CancelOrderDone(_msgSender(), vault_id_);
    }

    function executeSettlement(uint256 current_price_, uint256 timestamp_) external {
        require(_msgSender() == address(_settlement_manager), "Unauthorized call");
        address vault_address_ = address(_vault);

        uint256 prev_settlement_time_ = _prev_settlement_time;
        uint256 prev_settlement_price_ = _prev_settlement_price;

        ISwitchToken long_token_ = _long_token;
        ISwitchToken short_token_ = _short_token;

        uint256 price_per_token_ = pricePerToken();

        FeesParams memory fees_params_ = fees_params;

        uint256 total_fees_;

        if (prev_settlement_price_ != 0) {
            int256 pct_price_change_ = int256((current_price_ * 1 ether) / prev_settlement_price_) - 1 ether;

            uint256 long_tokens_ = long_token_.totalSupply();
            uint256 short_tokens_ = short_token_.totalSupply();
            uint256 total_tokens_;
            unchecked {
                total_tokens_ = long_tokens_ + short_tokens_;
            }

            if (total_tokens_ != 0) {
                uint256 m_ = _cycle_premium;

                uint256 short_token_ratio_;
                unchecked {
                    short_token_ratio_ = (short_tokens_ * 1 ether) / total_tokens_;

                    total_fees_ += (long_tokens_ * price_per_token_ * fees_params_.settlement_fees_long) / (1 ether * 1 ether);

                    total_fees_ += (short_tokens_ * price_per_token_ * fees_params_.settlement_fees_short) / (1 ether * 1 ether);
                }

                uint256 x_ = calcX(pct_price_change_);

                uint256 adj_factor_ = longTokenAdjustmentFactor(short_token_ratio_, m_, x_, fees_params_.settlement_fees_long);

                long_token_.runSettlement(adj_factor_);

                adj_factor_ = shortTokenAdjustmentFactor(short_token_ratio_, m_, x_, fees_params_.settlement_fees_short);

                short_token_.runSettlement(adj_factor_);
            }

            emit SettlementDone(long_tokens_, short_tokens_, long_token_.totalSupply(), short_token_.totalSupply());
        }

        _prev_settlement_price = current_price_;
        _prev_settlement_time = timestamp_;

        IERC20 settlement_token_ = _settlement_token;

        total_fees_ += _processWithdrawals(vault_address_, settlement_token_, long_token_, short_token_, price_per_token_, prev_settlement_time_, fees_params_);

        total_fees_ += _processSwitch(vault_address_, long_token_, short_token_, price_per_token_, prev_settlement_time_, fees_params_);

        total_fees_ += _processDeposits(vault_address_, settlement_token_, long_token_, short_token_, price_per_token_, prev_settlement_time_, fees_params_);

        if (total_fees_ > 0) settlement_token_.safeTransfer(address(_fee_collector), total_fees_);

        {
            uint256 total_tokens_;
            uint256 total_settlement_token_bal_ = settlement_token_.balanceOf(address(this));

            unchecked {
                total_tokens_ = long_token_.totalSupply() + short_token_.totalSupply();
            }

            if (total_tokens_ != 0) {
                unchecked {
                    uint256 adj_factor_ = (total_settlement_token_bal_ * 1 ether * 1 ether) / (total_tokens_ * price_per_token_);

                    long_token_.runSettlement(adj_factor_);
                    short_token_.runSettlement(adj_factor_);
                }
            }
        }
    }

    function scrapCycle(uint256 timestamp_) external {
        require(_msgSender() == address(_settlement_manager), "Unauthorized call");

        address vault_address_ = address(_vault);

        uint256 prev_settlement_time_ = _prev_settlement_time;

        _prev_settlement_time = timestamp_;
        _prev_settlement_price = 0;

        IERC20 settlement_token_ = _settlement_token;
        ISwitchToken long_token_ = _long_token;
        ISwitchToken short_token_ = _short_token;

        uint256 price_per_token_ = pricePerToken();

        FeesParams memory fees_params_ = fees_params;
        // fees_params_.loading_fees_long = 0;
        // fees_params_.loading_fees_short = 0;

        uint256 total_fees_ = _processWithdrawals(vault_address_, settlement_token_, long_token_, short_token_, price_per_token_, prev_settlement_time_, fees_params_);

        total_fees_ += _processSwitch(vault_address_, long_token_, short_token_, price_per_token_, prev_settlement_time_, fees_params_);

        total_fees_ += _processDeposits(vault_address_, settlement_token_, long_token_, short_token_, price_per_token_, prev_settlement_time_, fees_params_);

        if (total_fees_ > 0) settlement_token_.safeTransfer(address(_fee_collector), total_fees_);
    }

    function _processWithdrawals(address vault_address_, IERC20 settlement_token_, ISwitchToken long_token_, ISwitchToken short_token_, uint256 price_per_token_, uint256 prev_settlement_time_, FeesParams memory fees_params_) private returns (uint256 total_fees_) {
        uint256 settlement_amount_;
        uint256 fees_;

        uint256 total_settlement_token_bal_ = settlement_token_.balanceOf(address(this));

        uint256 vault_id_ = uint256(keccak256(abi.encodePacked(_LONG_TOKEN_WITHDRAWAL, prev_settlement_time_)));
        uint256 token_amount_ = IVault(vault_address_).makeDeposit(vault_id_, address(long_token_));

        if (token_amount_ != 0) {
            long_token_.burn(address(this), token_amount_);

            unchecked {
                settlement_amount_ = (token_amount_ * price_per_token_) / (1 ether);
                if (settlement_amount_ > total_settlement_token_bal_) {
                    settlement_amount_ = total_settlement_token_bal_;
                }

                total_settlement_token_bal_ -= settlement_amount_;

                fees_ = (settlement_amount_ * fees_params_.unloading_fees_long) / (1 ether);

                settlement_amount_ -= fees_;

                total_fees_ += fees_;
            }

            settlement_token_.safeTransfer(vault_address_, settlement_amount_);

            IVault(vault_address_).setClaimable(vault_id_, address(settlement_token_), settlement_amount_);
        }

        vault_id_ = uint256(keccak256(abi.encodePacked(_SHORT_TOKEN_WITHDRAWAL, prev_settlement_time_)));
        token_amount_ = IVault(vault_address_).makeDeposit(vault_id_, address(short_token_));

        if (token_amount_ != 0) {
            short_token_.burn(address(this), token_amount_);

            unchecked {
                settlement_amount_ = (token_amount_ * price_per_token_) / (1 ether);
                if (settlement_amount_ > total_settlement_token_bal_) {
                    settlement_amount_ = total_settlement_token_bal_;
                }

                total_settlement_token_bal_ -= settlement_amount_;

                fees_ = (settlement_amount_ * fees_params_.unloading_fees_short) / (1 ether);

                settlement_amount_ -= fees_;

                total_fees_ += fees_;
            }

            settlement_token_.safeTransfer(vault_address_, settlement_amount_);

            IVault(vault_address_).setClaimable(vault_id_, address(settlement_token_), settlement_amount_);
        }
    }
    function _processSwitch(address vault_address_, ISwitchToken long_token_, ISwitchToken short_token_, uint256 price_per_token_, uint256 prev_settlement_time_, FeesParams memory fees_params_) private returns (uint256 total_fees_) {
        uint256 vault_id_ = uint256(keccak256(abi.encodePacked(_LONG_TOKEN_SWITCH, prev_settlement_time_)));
        uint256 token_amount_ = IVault(vault_address_).makeDeposit(vault_id_, address(long_token_));

        if (token_amount_ != 0) {
            long_token_.burn(address(this), token_amount_);

            unchecked {
                uint256 fees_ = (token_amount_ * fees_params_.switching_fees_long) / (1 ether);

                token_amount_ -= fees_;

                total_fees_ += (fees_ * price_per_token_) / 1 ether;
            }

            token_amount_ = short_token_.convertToShares(token_amount_);
            short_token_.mintShares(vault_address_, token_amount_);

            IVault(vault_address_).setClaimable(vault_id_, address(short_token_), token_amount_);
        }

        vault_id_ = uint256(keccak256(abi.encodePacked(_SHORT_TOKEN_SWITCH, prev_settlement_time_)));
        token_amount_ = IVault(vault_address_).makeDeposit(vault_id_, address(short_token_));

        if (token_amount_ != 0) {
            short_token_.burn(address(this), token_amount_);

            unchecked {
                uint256 fees_ = (token_amount_ * fees_params_.switching_fees_short) / (1 ether);

                token_amount_ -= fees_;

                total_fees_ += (fees_ * price_per_token_) / 1 ether;
            }

            token_amount_ = long_token_.convertToShares(token_amount_);
            long_token_.mintShares(vault_address_, token_amount_);

            IVault(vault_address_).setClaimable(vault_id_, address(long_token_), token_amount_);
        }
    }

    function _processDeposits(address vault_address_, IERC20 settlement_token_, ISwitchToken long_token_, ISwitchToken short_token_, uint256 price_per_token_, uint256 prev_settlement_time_, FeesParams memory fees_params_) private returns (uint256 total_fees_) {
        uint256 vault_id_ = uint256(keccak256(abi.encodePacked(_LONG_TOKEN_DEPOSIT, prev_settlement_time_)));
        uint256 token_amount_ = IVault(vault_address_).makeDeposit(vault_id_, address(settlement_token_));

        if (token_amount_ != 0) {
            unchecked {
                uint256 fees_ = (token_amount_ * fees_params_.loading_fees_long) / (1 ether);

                total_fees_ += fees_;

                token_amount_ -= fees_;

                token_amount_ = long_token_.convertToShares((token_amount_ * 1 ether) / price_per_token_);

                long_token_.mintShares(vault_address_, token_amount_);

                IVault(vault_address_).setClaimable(vault_id_, address(long_token_), token_amount_);
            }
        }

        vault_id_ = uint256(keccak256(abi.encodePacked(_SHORT_TOKEN_DEPOSIT, prev_settlement_time_)));
        token_amount_ = IVault(vault_address_).makeDeposit(vault_id_, address(settlement_token_));

        if (token_amount_ != 0) {
            unchecked {
                uint256 fees_ = (token_amount_ * fees_params_.loading_fees_short) / (1 ether);

                total_fees_ += fees_;

                token_amount_ -= fees_;

                token_amount_ = short_token_.convertToShares((token_amount_ * 1 ether) / price_per_token_);

                short_token_.mintShares(vault_address_, token_amount_);

                IVault(vault_address_).setClaimable(vault_id_, address(short_token_), token_amount_);
            }
        }
    }

    uint256[47] private __gap;
}
