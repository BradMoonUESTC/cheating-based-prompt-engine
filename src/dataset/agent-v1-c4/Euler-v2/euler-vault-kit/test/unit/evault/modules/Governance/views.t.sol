// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {EVaultTestBase} from "../../EVaultTestBase.t.sol";

contract Governance_views is EVaultTestBase {
    function test_protocolFeeShare() public {
        assertEq(eTST.protocolFeeShare(), 0.1e4);

        startHoax(admin);
        protocolConfig.setProtocolFeeShare(0.4e4);

        assertEq(eTST.protocolFeeShare(), 0.4e4);
    }

    function test_protocolFeeReceiver() public {
        assertEq(eTST.protocolFeeReceiver(), protocolFeeReceiver);

        startHoax(admin);
        protocolConfig.setFeeReceiver(address(123));

        assertEq(eTST.protocolFeeReceiver(), address(123));
    }

    function test_LTVFull() public {
        address eTST3 = makeAddr("eTST3");

        (
            uint16 borrowLTV1,
            uint16 liquidationLTV1,
            uint16 initialLiquidationLTV1,
            uint48 targetTimestamp1,
            uint32 rampDuration1
        ) = eTST.LTVFull(address(eTST2));

        (
            uint16 borrowLTV2,
            uint16 liquidationLTV2,
            uint16 initialLiquidationLTV2,
            uint48 targetTimestamp2,
            uint32 rampDuration2
        ) = eTST.LTVFull(address(eTST3));

        assertEq(borrowLTV1, 0);
        assertEq(liquidationLTV1, 0);
        assertEq(initialLiquidationLTV1, 0);
        assertEq(targetTimestamp1, 0);
        assertEq(rampDuration1, 0);

        assertEq(borrowLTV2, 0);
        assertEq(liquidationLTV2, 0);
        assertEq(initialLiquidationLTV2, 0);
        assertEq(targetTimestamp2, 0);
        assertEq(rampDuration2, 0);

        eTST.setLTV(address(eTST2), 0.26e4, 0.3e4, 0);
        eTST.setLTV(eTST3, 0.16e4, 0.56e4, 0);

        (borrowLTV1, liquidationLTV1, initialLiquidationLTV1, targetTimestamp1, rampDuration1) =
            eTST.LTVFull(address(eTST2));
        (borrowLTV2, liquidationLTV2, initialLiquidationLTV2, targetTimestamp2, rampDuration2) = eTST.LTVFull(eTST3);

        assertEq(borrowLTV1, 0.26e4);
        assertEq(liquidationLTV1, 0.3e4);
        assertEq(initialLiquidationLTV1, 0);
        assertEq(targetTimestamp1, 1);
        assertEq(rampDuration1, 0);

        assertEq(borrowLTV2, 0.16e4);
        assertEq(liquidationLTV2, 0.56e4);
        assertEq(initialLiquidationLTV2, 0);
        assertEq(targetTimestamp2, 1);
        assertEq(rampDuration2, 0);

        skip(5000);

        eTST.setLTV(address(eTST2), 0.1e4, 0.15e4, 100);
        eTST.setLTV(eTST3, 0.09e4, 0.36e4, 1000);

        (borrowLTV1, liquidationLTV1, initialLiquidationLTV1, targetTimestamp1, rampDuration1) =
            eTST.LTVFull(address(eTST2));
        (borrowLTV2, liquidationLTV2, initialLiquidationLTV2, targetTimestamp2, rampDuration2) = eTST.LTVFull(eTST3);

        assertEq(borrowLTV1, 0.1e4);
        assertEq(liquidationLTV1, 0.15e4);
        assertEq(initialLiquidationLTV1, 0.3e4);
        assertEq(targetTimestamp1, 5001 + 100);
        assertEq(rampDuration1, 100);

        assertEq(borrowLTV2, 0.09e4);
        assertEq(liquidationLTV2, 0.36e4);
        assertEq(initialLiquidationLTV2, 0.56e4);
        assertEq(targetTimestamp2, 5001 + 1000);
        assertEq(rampDuration2, 1000);
    }

    function test_protocolConfigAddress() public view {
        assertEq(eTST.protocolConfigAddress(), address(protocolConfig));
    }

    function test_permit2Address() public view {
        assertEq(eTST.permit2Address(), permit2);
    }
}
