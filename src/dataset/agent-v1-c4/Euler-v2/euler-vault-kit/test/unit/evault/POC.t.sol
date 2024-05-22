// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {EVaultTestBase} from "./EVaultTestBase.t.sol";
import "../../../src/EVault/shared/types/Types.sol";
import "../../../src/EVault/shared/Constants.sol";

contract POC_Test is EVaultTestBase {
    using TypesLib for uint256;

    function setUp() public override {
        // There are 2 vaults deployed with bare minimum configuration:
        // - eTST vault using assetTST as the underlying
        // - eTST2 vault using assetTST2 as the underlying

        // Both vaults use the same MockPriceOracle and unit of account.
        // Both vaults are configured to use IRMTestDefault interest rate model.
        // Both vaults are configured to use 0.2e4 max liquidation discount.
        // Neither price oracles for the assets nor the LTVs are set.
        super.setUp();

        // In order to further configure the vaults, refer to the Governance module functions.
    }

    function test_POC() external {}
}
