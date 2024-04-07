// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAggregationExecutorOptimistic as IExecutorHelperL2} from "../interfaces/IAggregationExecutorOptimistic.sol";
import {IExecutorHelper as IExecutorHelperL1} from "../interfaces/IExecutorHelper.sol";
import {IMetaAggregationRouterV2} from "../interfaces/IMetaAggregationRouterV2.sol";
import {ScalingDataL2Lib} from "./ScalingDataL2Lib.sol";
import {ExecutorReader} from "./ExecutorReader.sol";
import {CalldataWriter} from "./CalldataWriter.sol";

library InputScalingHelperL2 {
    using ExecutorReader for bytes;
    using ScalingDataL2Lib for bytes;

    uint256 private constant _PARTIAL_FILL = 0x01;
    uint256 private constant _REQUIRES_EXTRA_ETH = 0x02;
    uint256 private constant _SHOULD_CLAIM = 0x04;
    uint256 private constant _BURN_FROM_MSG_SENDER = 0x08;
    uint256 private constant _BURN_FROM_TX_ORIGIN = 0x10;
    uint256 private constant _SIMPLE_SWAP = 0x20;

    struct PositiveSlippageFeeData {
        uint256 partnerPSInfor;
        uint256 expectedReturnAmount;
    }

    enum DexIndex {
        UNI,
        KyberDMM,
        Velodrome,
        Fraxswap,
        Camelot,
        KyberLO,
        RFQ,
        Hashflow,
        StableSwap,
        Curve,
        UniswapV3KSElastic,
        BalancerV2,
        DODO,
        GMX,
        Synthetix,
        wstETH,
        stETH,
        Platypus,
        PSM,
        Maverick,
        SyncSwap,
        AlgebraV1,
        BalancerBatch,
        Mantis,
        Wombat,
        WooFiV2,
        iZiSwap,
        TraderJoeV2,
        KyberDSLO,
        LevelFiV2,
        GMXGLP,
        PancakeStableSwap,
        Vooi,
        VelocoreV2,
        Smardex,
        SolidlyV2,
        Kokonut,
        BalancerV1,
        SwaapV2,
        NomiswapStable,
        ArbswapStable,
        BancorV3,
        BancorV2,
        Ambient,
        Native,
        LighterV2,
        Bebop
    }

    function _getScaledInputData(bytes calldata inputData, uint256 newAmount) internal pure returns (bytes memory) {
        bytes4 selector = bytes4(inputData[:4]);
        bytes calldata dataToDecode = inputData[4:];

        if (selector == IMetaAggregationRouterV2.swap.selector) {
            IMetaAggregationRouterV2.SwapExecutionParams memory params = abi.decode(
                dataToDecode,
                (IMetaAggregationRouterV2.SwapExecutionParams)
            );

            (params.desc, params.targetData) = _getScaledInputDataV2(
                params.desc,
                params.targetData,
                newAmount,
                _flagsChecked(params.desc.flags, _SIMPLE_SWAP)
            );
            return abi.encodeWithSelector(selector, params);
        } else if (selector == IMetaAggregationRouterV2.swapSimpleMode.selector) {
            (
                address callTarget,
                IMetaAggregationRouterV2.SwapDescriptionV2 memory desc,
                bytes memory targetData,
                bytes memory clientData
            ) = abi.decode(dataToDecode, (address, IMetaAggregationRouterV2.SwapDescriptionV2, bytes, bytes));

            (desc, targetData) = _getScaledInputDataV2(desc, targetData, newAmount, true);
            return abi.encodeWithSelector(selector, callTarget, desc, targetData, clientData);
        } else {
            revert("InputScalingHelper: Invalid selector");
        }
    }

    function _getScaledInputDataV2(
        IMetaAggregationRouterV2.SwapDescriptionV2 memory desc,
        bytes memory executorData,
        uint256 newAmount,
        bool isSimpleMode
    ) internal pure returns (IMetaAggregationRouterV2.SwapDescriptionV2 memory, bytes memory) {
        uint256 oldAmount = desc.amount;
        if (oldAmount == newAmount) {
            return (desc, executorData);
        }

        // simple mode swap
        if (isSimpleMode) {
            return (
                _scaledSwapDescriptionV2(desc, oldAmount, newAmount),
                _scaledSimpleSwapData(executorData, oldAmount, newAmount)
            );
        }

        //normal mode swap
        return (
            _scaledSwapDescriptionV2(desc, oldAmount, newAmount),
            _scaledExecutorCallBytesData(executorData, oldAmount, newAmount)
        );
    }

    /// @dev Scale the swap description
    function _scaledSwapDescriptionV2(
        IMetaAggregationRouterV2.SwapDescriptionV2 memory desc,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (IMetaAggregationRouterV2.SwapDescriptionV2 memory) {
        desc.minReturnAmount = (desc.minReturnAmount * newAmount) / oldAmount;
        if (desc.minReturnAmount == 0) desc.minReturnAmount = 1;
        desc.amount = (desc.amount * newAmount) / oldAmount;

        uint256 nReceivers = desc.srcReceivers.length;
        for (uint256 i = 0; i < nReceivers; ) {
            desc.srcAmounts[i] = (desc.srcAmounts[i] * newAmount) / oldAmount;
            unchecked {
                ++i;
            }
        }
        return desc;
    }

    /// @dev Scale the executorData in case swapSimpleMode
    function _scaledSimpleSwapData(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IMetaAggregationRouterV2.SimpleSwapData memory simpleSwapData = abi.decode(
            data,
            (IMetaAggregationRouterV2.SimpleSwapData)
        );
        uint256 nPools = simpleSwapData.firstPools.length;
        address tokenIn;

        for (uint256 i = 0; i < nPools; ) {
            simpleSwapData.firstSwapAmounts[i] = (simpleSwapData.firstSwapAmounts[i] * newAmount) / oldAmount;

            IExecutorHelperL2.Swap[] memory dexData;

            (dexData, tokenIn) = simpleSwapData.swapDatas[i].readSwapSingleSequence();

            // only need to scale the first dex in each sequence
            if (dexData.length > 0) {
                dexData[0] = _scaleDexData(dexData[0], oldAmount, newAmount);
            }

            simpleSwapData.swapDatas[i] = CalldataWriter._writeSwapSingleSequence(abi.encode(dexData), tokenIn);

            unchecked {
                ++i;
            }
        }

        simpleSwapData.positiveSlippageData = _scaledPositiveSlippageFeeData(
            simpleSwapData.positiveSlippageData,
            oldAmount,
            newAmount
        );

        return abi.encode(simpleSwapData);
    }

    /// @dev Scale the executorData in case normal swap
    function _scaledExecutorCallBytesData(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelperL2.SwapExecutorDescription memory executorDesc = abi.decode(
            data.readSwapExecutorDescription(),
            (IExecutorHelperL2.SwapExecutorDescription)
        );

        executorDesc.positiveSlippageData = _scaledPositiveSlippageFeeData(
            executorDesc.positiveSlippageData,
            oldAmount,
            newAmount
        );

        uint256 nSequences = executorDesc.swapSequences.length;
        for (uint256 i = 0; i < nSequences; ) {
            // only need to scale the first dex in each sequence
            IExecutorHelperL2.Swap memory swap = executorDesc.swapSequences[i][0];
            executorDesc.swapSequences[i][0] = _scaleDexData(swap, oldAmount, newAmount);
            unchecked {
                ++i;
            }
        }
        return CalldataWriter.writeSwapExecutorDescription(executorDesc);
    }

    function _scaledPositiveSlippageFeeData(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory newData) {
        if (data.length > 32) {
            PositiveSlippageFeeData memory psData = abi.decode(data, (PositiveSlippageFeeData));
            uint256 left = uint256(psData.expectedReturnAmount >> 128);
            uint256 right = (uint256(uint128(psData.expectedReturnAmount)) * newAmount) / oldAmount;
            require(right <= type(uint128).max, "_scaledPositiveSlippageFeeData/Exceeded type range");
            psData.expectedReturnAmount = right | (left << 128);
            data = abi.encode(psData);
        } else if (data.length == 32) {
            uint256 expectedReturnAmount = abi.decode(data, (uint256));
            uint256 left = uint256(expectedReturnAmount >> 128);
            uint256 right = (uint256(uint128(expectedReturnAmount)) * newAmount) / oldAmount;
            require(right <= type(uint128).max, "_scaledPositiveSlippageFeeData/Exceeded type range");
            expectedReturnAmount = right | (left << 128);
            data = abi.encode(expectedReturnAmount);
        }
        return data;
    }

    function _scaleDexData(
        IExecutorHelperL2.Swap memory swap,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (IExecutorHelperL2.Swap memory) {
        uint8 functionSelectorIndex = uint8(uint32(swap.functionSelector));

        if (DexIndex(functionSelectorIndex) == DexIndex.UNI) {
            swap.data = swap.data.newUniSwap(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.StableSwap) {
            swap.data = swap.data.newStableSwap(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.Curve) {
            swap.data = swap.data.newCurveSwap(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.KyberDMM) {
            swap.data = swap.data.newKyberDMM(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.UniswapV3KSElastic) {
            swap.data = swap.data.newUniswapV3KSElastic(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.RFQ) {
            revert("InputScalingHelper: Can not scale RFQ swap");
        } else if (DexIndex(functionSelectorIndex) == DexIndex.BalancerV2) {
            swap.data = swap.data.newBalancerV2(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.wstETH) {
            swap.data = swap.data.newWrappedstETHSwap(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.stETH) {
            swap.data = swap.data.newStETHSwap(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.DODO) {
            swap.data = swap.data.newDODO(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.Velodrome) {
            swap.data = swap.data.newVelodrome(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.GMX) {
            swap.data = swap.data.newGMX(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.Synthetix) {
            swap.data = swap.data.newSynthetix(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.Hashflow) {
            revert("InputScalingHelper: Can not scale Hashflow swap");
        } else if (DexIndex(functionSelectorIndex) == DexIndex.Camelot) {
            swap.data = swap.data.newCamelot(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.KyberLO) {
            revert("InputScalingHelper: Can not scale KyberLO swap");
        } else if (DexIndex(functionSelectorIndex) == DexIndex.PSM) {
            swap.data = swap.data.newPSM(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.Fraxswap) {
            swap.data = swap.data.newFrax(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.Platypus) {
            swap.data = swap.data.newPlatypus(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.Maverick) {
            swap.data = swap.data.newMaverick(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.SyncSwap) {
            swap.data = swap.data.newSyncSwap(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.AlgebraV1) {
            swap.data = swap.data.newAlgebraV1(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.BalancerBatch) {
            swap.data = swap.data.newBalancerBatch(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.Mantis) {
            swap.data = swap.data.newMantis(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.Wombat) {
            swap.data = swap.data.newMantis(oldAmount, newAmount); // @dev use identical calldata structure as Mantis
        } else if (DexIndex(functionSelectorIndex) == DexIndex.iZiSwap) {
            swap.data = swap.data.newIziSwap(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.TraderJoeV2) {
            swap.data = swap.data.newTraderJoeV2(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.WooFiV2) {
            swap.data = swap.data.newMantis(oldAmount, newAmount); // @dev use identical calldata structure as Mantis
        } else if (DexIndex(functionSelectorIndex) == DexIndex.KyberDSLO) {
            revert("InputScalingHelper: Can not scale KyberDSLO swap");
        } else if (DexIndex(functionSelectorIndex) == DexIndex.LevelFiV2) {
            swap.data = swap.data.newLevelFiV2(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.PancakeStableSwap) {
            swap.data = swap.data.newCurveSwap(oldAmount, newAmount); // @dev same encoded data as Curve
        } else if (DexIndex(functionSelectorIndex) == DexIndex.GMXGLP) {
            swap.data = swap.data.newGMXGLP(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.Vooi) {
            swap.data = swap.data.newVooi(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.VelocoreV2) {
            swap.data = swap.data.newVelocoreV2(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.Smardex) {
            swap.data = swap.data.newMantis(oldAmount, newAmount); // @dev use identical calldata structure as Mantis
        } else if (DexIndex(functionSelectorIndex) == DexIndex.SolidlyV2) {
            swap.data = swap.data.newMantis(oldAmount, newAmount); // @dev use identical calldata structure as Mantis
        } else if (DexIndex(functionSelectorIndex) == DexIndex.Kokonut) {
            swap.data = swap.data.newKokonut(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.BalancerV1) {
            swap.data = swap.data.newBalancerV1(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.SwaapV2) {
            revert("InputScalingHelper: Can not scale SwaapV2 swap");
        } else if (DexIndex(functionSelectorIndex) == DexIndex.NomiswapStable) {
            swap.data = swap.data.newMantis(oldAmount, newAmount); // @dev use identical calldata structure as Mantis
        } else if (DexIndex(functionSelectorIndex) == DexIndex.ArbswapStable) {
            swap.data = swap.data.newArbswapStable(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.BancorV2) {
            swap.data = swap.data.newBancorV2(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.BancorV3) {
            swap.data = swap.data.newMantis(oldAmount, newAmount); // @dev use identical calldata structure as Mantis
        } else if (DexIndex(functionSelectorIndex) == DexIndex.Ambient) {
            swap.data = swap.data.newAmbient(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.Native) {
            revert("InputScalingHelper: Can not scale Native swap");
        } else if (DexIndex(functionSelectorIndex) == DexIndex.LighterV2) {
            swap.data = swap.data.newLighterV2(oldAmount, newAmount);
        } else if (DexIndex(functionSelectorIndex) == DexIndex.Bebop) {
            revert("InputScalingHelper: Can not scale Bebop swap");
        } else {
            revert("InputScaleHelper: Dex type not supported");
        }
        return swap;
    }

    function _flagsChecked(uint256 number, uint256 flag) internal pure returns (bool) {
        return number & flag != 0;
    }
}
