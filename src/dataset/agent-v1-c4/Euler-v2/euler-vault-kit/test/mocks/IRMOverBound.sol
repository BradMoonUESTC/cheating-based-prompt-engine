// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "../../src/InterestRateModels/IIRM.sol";
import "../../src/EVault/shared/Constants.sol";

contract IRMOverBound is IIRM {
    function computeInterestRate(address vault, uint256, uint256) external view override returns (uint256) {
        if (msg.sender != vault) revert E_IRMUpdateUnauthorized();
        return MAX_ALLOWED_INTEREST_RATE + 100;
    }

    function computeInterestRateView(address, uint256, uint256) external pure override returns (uint256) {
        return MAX_ALLOWED_INTEREST_RATE + 100;
    }
}
