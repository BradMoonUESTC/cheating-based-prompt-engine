// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IExecutorHelper} from "../interfaces/IExecutorHelper.sol";
import {DexScaler} from "./DexScaler.sol";

library ScalingDataL2Lib {
    using DexScaler for bytes;

    function newUniSwap(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        return data.scaleUniSwap(oldAmount, newAmount);
    }

    function newStableSwap(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        return data.scaleStableSwap(oldAmount, newAmount);
    }

    function newCurveSwap(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        return data.scaleCurveSwap(oldAmount, newAmount);
    }

    function newKyberDMM(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        return data.scaleUniSwap(oldAmount, newAmount);
    }

    function newUniswapV3KSElastic(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        return data.scaleUniswapV3KSElastic(oldAmount, newAmount);
    }

    function newBalancerV2(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        return data.scaleBalancerV2(oldAmount, newAmount);
    }

    function newDODO(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        return data.scaleDODO(oldAmount, newAmount);
    }

    function newVelodrome(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        return data.scaleUniSwap(oldAmount, newAmount);
    }

    function newGMX(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        return data.scaleGMX(oldAmount, newAmount);
    }

    function newSynthetix(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        return data.scaleSynthetix(oldAmount, newAmount);
    }

    function newCamelot(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        return data.scaleUniSwap(oldAmount, newAmount);
    }

    function newPlatypus(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        return data.scalePlatypus(oldAmount, newAmount);
    }

    function newWrappedstETHSwap(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        return data.scaleWrappedstETH(oldAmount, newAmount);
    }

    function newPSM(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        return data.scalePSM(oldAmount, newAmount);
    }

    function newFrax(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        return data.scaleUniSwap(oldAmount, newAmount);
    }

    function newStETHSwap(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        return data.scaleStETH(oldAmount, newAmount);
    }

    function newMaverick(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        return data.scaleMaverick(oldAmount, newAmount);
    }

    function newSyncSwap(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        return data.scaleSyncSwap(oldAmount, newAmount);
    }

    function newAlgebraV1(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        return data.scaleAlgebraV1(oldAmount, newAmount);
    }

    function newBalancerBatch(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        return data.scaleBalancerBatch(oldAmount, newAmount);
    }

    function newMantis(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        return data.scaleMantis(oldAmount, newAmount);
    }

    function newIziSwap(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        return data.scaleIziSwap(oldAmount, newAmount);
    }

    function newTraderJoeV2(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        return data.scaleTraderJoeV2(oldAmount, newAmount);
    }

    function newLevelFiV2(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        return data.scaleLevelFiV2(oldAmount, newAmount);
    }

    function newGMXGLP(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        return data.scaleGMXGLP(oldAmount, newAmount);
    }

    function newVooi(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        return data.scaleVooi(oldAmount, newAmount);
    }

    function newVelocoreV2(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        return data.scaleVelocoreV2(oldAmount, newAmount);
    }

    function newKokonut(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        return data.scaleKokonut(oldAmount, newAmount);
    }

    function newBalancerV1(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        return data.scaleBalancerV1(oldAmount, newAmount);
    }

    function newArbswapStable(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        return data.scaleArbswapStable(oldAmount, newAmount);
    }

    function newBancorV2(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        return data.scaleBancorV2(oldAmount, newAmount);
    }

    function newAmbient(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        return data.scaleAmbient(oldAmount, newAmount);
    }

    function newLighterV2(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        return data.scaleLighterV2(oldAmount, newAmount);
    }
}
