// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {IVault} from "./IVault.sol";

interface IRefinance {
    function vault() external view returns (IVault);

    function getBeforeRefinanceETHShare() external view returns (uint256);

    function getAfterRefinanceETHShare() external view returns (uint256);

    function feeUlpTracker() external view returns (address);
}
