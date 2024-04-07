// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./PendleGaugeControllerBaseUpg.sol";
import "../CrossChainMsg/PendleMsgReceiverAppUpg.sol";

// solhint-disable no-empty-blocks

contract PendleGaugeControllerSidechainUpg is PendleGaugeControllerBaseUpg, PendleMsgReceiverAppUpg {
    constructor(
        address _pendle,
        address _marketFactory,
        address _marketFactory2,
        address _PendleMsgReceiveEndpointUpg
    )
        PendleGaugeControllerBaseUpg(_pendle, _marketFactory, _marketFactory2)
        PendleMsgReceiverAppUpg(_PendleMsgReceiveEndpointUpg)
    {
        _disableInitializers();
    }

    function initialize() external initializer {
        __BoringOwnable_init();
    }

    function _executeMessage(bytes memory message) internal virtual override {
        (uint128 wTime, address[] memory markets, uint256[] memory pendleAmounts) = abi.decode(
            message,
            (uint128, address[], uint256[])
        );
        _receiveVotingResults(wTime, markets, pendleAmounts);
    }
}
