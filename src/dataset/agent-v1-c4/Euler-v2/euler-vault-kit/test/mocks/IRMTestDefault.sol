// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "../../src/InterestRateModels/IRMLinearKink.sol";

contract IRMTestDefault is IRMLinearKink {
    constructor()
        // Base=0% APY,  Kink(50%)=10% APY  Max=300% APY
        IRMLinearKink(0, 1406417851, 19050045013, 2147483648)
    {}
}
