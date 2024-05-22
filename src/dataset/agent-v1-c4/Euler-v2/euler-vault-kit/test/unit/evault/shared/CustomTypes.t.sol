// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "../EVaultTestBase.t.sol";

contract CustomTypesTest is EVaultTestBase {
    using TypesLib for uint256;

    function test_maxOwedAndAssetsConversions() external pure {
        require(MAX_SANE_DEBT_AMOUNT.toOwed().toAssetsUp().toUint() == MAX_SANE_AMOUNT, "owed to assets up");
        require(MAX_SANE_AMOUNT.toAssets().toOwed().toUint() == MAX_SANE_DEBT_AMOUNT, "assets to owed");
    }
}
