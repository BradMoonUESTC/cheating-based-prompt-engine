// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {CallbackLib} from "@libraries/CallbackLib.sol";
import {IUniswapV3Factory} from "v3-core/interfaces/IUniswapV3Factory.sol";

/// @title CallbackLib: A harness to expose the CallbackLib library for code coverage analysis.
/// @notice Replicates the interface of the CallbackLib library, passing through any function calls
/// @author Axicon Labs Limited
contract CallbackLibHarness {
    function validateCallback(
        address sender,
        IUniswapV3Factory factory,
        CallbackLib.PoolFeatures memory features
    ) public view {
        CallbackLib.validateCallback(sender, factory, features);
    }
}
