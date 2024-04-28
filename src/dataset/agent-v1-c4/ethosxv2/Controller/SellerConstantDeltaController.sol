// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ControllerBase} from "./ControllerBase.sol";

contract SellerConstantDeltaController is ControllerBase {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function __SellerConstantDeltaController_init(int8 opt_type_, uint256 cycle_premium_, uint256 payoff_cap_, address long_token_address_, address short_token_address_, address settlement_token_address_) public initializer {
        __ControllerBase_init(opt_type_, cycle_premium_, payoff_cap_, long_token_address_, short_token_address_, settlement_token_address_);
    }

    /** The following two functions assume that the number of decimals of Switch are the same as the number of decimals of the collateral token
     *  This is being enforced in the SwitchToken contract
     */
    function lastSettlementPricePerToken() public view override returns (uint256) {
        return 1 ether;
    }

    function pricePerToken() public view override returns (uint256) {
        return 1 ether;
    }

    function longTokenAdjustmentFactor(uint256 short_token_ratio_, uint256 m_, uint256 x_, uint256 fees_pct_) internal pure override returns (uint256 adjustment_factor_) {
        if (short_token_ratio_ == 0 || short_token_ratio_ == 1 ether) {
            return 1 ether;
        }

        adjustment_factor_ = (1 ether + ((x_ * short_token_ratio_) / (1 ether - short_token_ratio_)) - m_ - fees_pct_);
    }

    function shortTokenAdjustmentFactor(uint256 short_token_ratio_, uint256 m_, uint256 x_, uint256 fees_pct_) internal pure override returns (uint256 adjustment_factor_) {
        if (short_token_ratio_ == 0 || short_token_ratio_ == 1 ether) {
            return 1 ether;
        }

        adjustment_factor_ = (1 ether + ((m_ * (1 ether - short_token_ratio_)) / short_token_ratio_) - x_ - fees_pct_);
    }

    function calcX(int256 pct_price_change_) internal view override returns (uint256 x_) {
        if (optType() * pct_price_change_ >= 0) {
            if (pct_price_change_ < 0) {
                x_ = uint256(-1 * pct_price_change_);
            } else {
                x_ = uint256(pct_price_change_);
            }
        }

        if (x_ > _payoff_cap) {
            x_ = _payoff_cap;
        }
    }

    uint256[50] private __gap;
}
