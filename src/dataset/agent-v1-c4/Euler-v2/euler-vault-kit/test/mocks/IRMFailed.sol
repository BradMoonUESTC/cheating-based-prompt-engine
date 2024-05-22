// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "../../src/InterestRateModels/IIRM.sol";

contract IRMFailed is IIRM {
    function computeInterestRate(address, uint256, uint256) external pure override returns (uint256) {
        revert();
    }

    function computeInterestRateView(address, uint256, uint256) external pure override returns (uint256) {
        revert();
    }
}
