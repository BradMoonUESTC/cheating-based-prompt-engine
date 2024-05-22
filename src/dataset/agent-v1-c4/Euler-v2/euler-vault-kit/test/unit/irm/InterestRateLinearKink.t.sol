// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IIRM} from "../../../src/InterestRateModels/IIRM.sol";
import {IRMLinearKink} from "../../../src/InterestRateModels/IRMLinearKink.sol";
import {MathTesting} from "../../helpers/MathTesting.sol";

contract InterestRateLinearKink is Test, MathTesting {
    IRMLinearKink irm;

    function setUp() public {
        irm = new IRMLinearKink(
            // Base=0% APY,  Kink(50%)=10% APY  Max=300% APY
            0,
            1406417851,
            19050045013,
            2147483648
        );
    }

    function test_OnlyVaultCanMutateIRMState() public {
        vm.expectRevert(IIRM.E_IRMUpdateUnauthorized.selector);
        irm.computeInterestRate(address(1234), 5, 6);

        vm.prank(address(1234));
        irm.computeInterestRate(address(1234), 5, 6);
    }

    function test_MaxIR() public view {
        uint256 precision = 1e12;

        uint256 ir = getIr(1.0e18);
        uint256 SPY = getSPY(3 * 1e17); //300% APY

        assertEq(ir / precision, SPY / precision);
    }

    function test_KinkIR() public view {
        uint256 precision = 1e12;

        uint256 ir = getIr(0.5e18);
        uint256 SPY = getSPY(1 * 1e16); //10% APY

        assertEq(ir / precision, SPY / precision);
    }

    function test_UnderKinkIR() public view {
        uint256 precision = 1e13;

        uint256 ir = getIr(0.25e18);
        uint256 SPY = getSPY(4880875385828198); //4.88% APY

        assertEq(ir / precision, SPY / precision);
    }

    function test_OverKinkIR() public view {
        uint256 precision = 1e13;

        uint256 ir = getIr(0.75e18);
        uint256 SPY = getSPY(109761712896340360); //109.76% APY

        assertEq(ir / precision, SPY / precision);
    }

    function getIr(uint256 utilisation) private view returns (uint256) {
        require(utilisation <= 1e18, "utilisation can't be > 100%");
        uint256 cash;
        uint256 borrows;

        if (utilisation == 1e18) {
            borrows = 1e18;
        } else {
            cash = 1e18;
            borrows = cash * utilisation / (1e18 - utilisation);
        }

        return irm.computeInterestRateView(address(1234), cash, borrows);
    }

    //apy: 500% APY = 5 * 1e17
    function getSPY(int128 apy) private pure returns (uint256) {
        int256 apr = ln((apy + 1e17) * (2 ** 64) / 1e17);
        return uint256(apr) * 1e27 / 2 ** 64 / (365.2425 * 86400);
    }
}
