// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {ESVaultTestBase} from "./ESVaultTestBase.t.sol";
import {Errors} from "../../../src/EVault/shared/Errors.sol";

contract ESVaultTestInterestFee is ESVaultTestBase {
    function setUp() public override {
        super.setUp();
    }

    function test_interest_fee() public view {
        uint256 interestFee = eTST.interestFee();
        assertEq(interestFee, 1e4);
    }

    function test_set_interest_fee() public {
        // This protection is not currently implemented. A governor can change the interestFee
        // of a synth vault to a non-100% value. Don't do that.

        //vm.expectRevert(Errors.E_OperationDisabled.selector);
        //eTST.setInterestFee(0.5e4);
    }
}
