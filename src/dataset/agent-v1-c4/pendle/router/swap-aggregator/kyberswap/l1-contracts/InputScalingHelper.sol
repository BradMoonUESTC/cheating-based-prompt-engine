// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IExecutorHelper} from "../interfaces/IExecutorHelper.sol";
import {IMetaAggregationRouterV2} from "../interfaces/IMetaAggregationRouterV2.sol";
import {ScalingDataLib} from "./ScalingDataLib.sol";

/* ----------------------------------------
.__   __.   ______   .___________. _______
|  \ |  |  /  __  \  |           ||   ____|
|   \|  | |  |  |  | `---|  |----`|  |__
|  . `  | |  |  |  |     |  |     |   __|
|  |\   | |  `--'  |     |  |     |  |____
|__| \__|  \______/      |__|     |_______|


Please use InputScalingHelperL2 contract for scaling data on Arbitrum, Optimism, Base

---------------------------------------- */

library InputScalingHelper {
    uint256 private constant _PARTIAL_FILL = 0x01;
    uint256 private constant _REQUIRES_EXTRA_ETH = 0x02;
    uint256 private constant _SHOULD_CLAIM = 0x04;
    uint256 private constant _BURN_FROM_MSG_SENDER = 0x08;
    uint256 private constant _BURN_FROM_TX_ORIGIN = 0x10;
    uint256 private constant _SIMPLE_SWAP = 0x20;

    // fee data in case taking in dest token
    struct PositiveSlippageFeeData {
        uint256 partnerPSInfor; // [partnerReceiver (160 bit) + partnerPercent(96bits)]
        uint256 expectedReturnAmount;
    }

    struct Swap {
        bytes data;
        bytes32 selectorAndFlags; // [selector (32 bits) + flags (224 bits)]; selector is 4 most significant bytes; flags are stored in 4 least significant bytes.
    }

    struct SimpleSwapData {
        address[] firstPools;
        uint256[] firstSwapAmounts;
        bytes[] swapDatas;
        uint256 deadline;
        bytes positiveSlippageData;
    }

    struct SwapExecutorDescription {
        Swap[][] swapSequences;
        address tokenIn;
        address tokenOut;
        address to;
        uint256 deadline;
        bytes positiveSlippageData;
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
        desc.amount = newAmount;

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
        SimpleSwapData memory swapData = abi.decode(data, (SimpleSwapData));

        uint256 nPools = swapData.firstPools.length;
        for (uint256 i = 0; i < nPools; ) {
            swapData.firstSwapAmounts[i] = (swapData.firstSwapAmounts[i] * newAmount) / oldAmount;
            unchecked {
                ++i;
            }
        }
        swapData.positiveSlippageData = _scaledPositiveSlippageFeeData(
            swapData.positiveSlippageData,
            oldAmount,
            newAmount
        );
        return abi.encode(swapData);
    }

    /// @dev Scale the executorData in case normal swap
    function _scaledExecutorCallBytesData(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        SwapExecutorDescription memory executorDesc = abi.decode(data, (SwapExecutorDescription));
        executorDesc.positiveSlippageData = _scaledPositiveSlippageFeeData(
            executorDesc.positiveSlippageData,
            oldAmount,
            newAmount
        );

        uint256 nSequences = executorDesc.swapSequences.length;
        for (uint256 i = 0; i < nSequences; ) {
            Swap memory swap = executorDesc.swapSequences[i][0];
            bytes4 functionSelector = bytes4(swap.selectorAndFlags);

            if (functionSelector == IExecutorHelper.executeUniswap.selector) {
                swap.data = ScalingDataLib.newUniSwap(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeStableSwap.selector) {
                swap.data = ScalingDataLib.newStableSwap(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeCurve.selector) {
                swap.data = ScalingDataLib.newCurveSwap(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeKSClassic.selector) {
                swap.data = ScalingDataLib.newKyberDMM(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeUniV3KSElastic.selector) {
                swap.data = ScalingDataLib.newUniV3ProMM(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeRfq.selector) {
                revert("InputScalingHelper: Can not scale RFQ swap");
            } else if (functionSelector == IExecutorHelper.executeBalV2.selector) {
                swap.data = ScalingDataLib.newBalancerV2(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeWrappedstETH.selector) {
                swap.data = ScalingDataLib.newWrappedstETHSwap(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeStEth.selector) {
                swap.data = ScalingDataLib.newStETHSwap(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeDODO.selector) {
                swap.data = ScalingDataLib.newDODO(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeVelodrome.selector) {
                swap.data = ScalingDataLib.newVelodrome(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeGMX.selector) {
                swap.data = ScalingDataLib.newGMX(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeSynthetix.selector) {
                swap.data = ScalingDataLib.newSynthetix(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeHashflow.selector) {
                revert("InputScalingHelper: Can not scale Hasflow swap");
            } else if (functionSelector == IExecutorHelper.executeCamelot.selector) {
                swap.data = ScalingDataLib.newCamelot(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeKyberLimitOrder.selector) {
                revert("InputScalingHelper: Can not scale KyberLO swap");
            } else if (functionSelector == IExecutorHelper.executePSM.selector) {
                swap.data = ScalingDataLib.newPSM(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeFrax.selector) {
                swap.data = ScalingDataLib.newFrax(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executePlatypus.selector) {
                swap.data = ScalingDataLib.newPlatypus(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeMaverick.selector) {
                swap.data = ScalingDataLib.newMaverick(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeSyncSwap.selector) {
                swap.data = ScalingDataLib.newSyncSwap(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeAlgebraV1.selector) {
                swap.data = ScalingDataLib.newAlgebraV1(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeBalancerBatch.selector) {
                swap.data = ScalingDataLib.newBalancerBatch(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeWombat.selector) {
                swap.data = ScalingDataLib.newMantis(swap.data, oldAmount, newAmount); // @dev struct Mantis is used for both Wombat and Mantis because of same fields
            } else if (functionSelector == IExecutorHelper.executeMantis.selector) {
                swap.data = ScalingDataLib.newMantis(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeIziSwap.selector) {
                swap.data = ScalingDataLib.newIziSwap(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeWooFiV2.selector) {
                swap.data = ScalingDataLib.newMantis(swap.data, oldAmount, newAmount); // @dev using Mantis struct because WooFiV2 and Mantis have same fields
            } else if (functionSelector == IExecutorHelper.executeTraderJoeV2.selector) {
                swap.data = ScalingDataLib.newTraderJoeV2(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executePancakeStableSwap.selector) {
                swap.data = ScalingDataLib.newCurveSwap(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeLevelFiV2.selector) {
                swap.data = ScalingDataLib.newLevelFiV2(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeGMXGLP.selector) {
                swap.data = ScalingDataLib.newGMXGLP(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeVooi.selector) {
                swap.data = ScalingDataLib.newVooi(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeVelocoreV2.selector) {
                swap.data = ScalingDataLib.newVelocoreV2(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeMaticMigrate.selector) {
                swap.data = ScalingDataLib.newMaticMigrate(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeSmardex.selector) {
                swap.data = ScalingDataLib.newMantis(swap.data, oldAmount, newAmount); // @dev using Mantis struct because Smardex and Mantis have same fields
            } else if (functionSelector == IExecutorHelper.executeSolidlyV2.selector) {
                swap.data = ScalingDataLib.newMantis(swap.data, oldAmount, newAmount); // @dev using Mantis struct because Solidly V2 and Mantis have same fields
            } else if (functionSelector == IExecutorHelper.executeKokonut.selector) {
                swap.data = ScalingDataLib.newKokonut(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeBalancerV1.selector) {
                swap.data = ScalingDataLib.newBalancerV1(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeSwaapV2.selector) {
                revert("InputScalingHelper: Can not scale SwaapV2 swap");
            } else if (functionSelector == IExecutorHelper.executeNomiswapStable.selector) {
                swap.data = ScalingDataLib.newMantis(swap.data, oldAmount, newAmount); // @dev using Mantis struct because NomiswapV2 and Mantis have same fields
            } else if (functionSelector == IExecutorHelper.executeArbswapStable.selector) {
                swap.data = ScalingDataLib.newArbswapStable(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeBancorV2.selector) {
                swap.data = ScalingDataLib.newBancorV2(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeBancorV3.selector) {
                swap.data = ScalingDataLib.newMantis(swap.data, oldAmount, newAmount); // @dev using Mantis struct because Bancor V3 and Mantis have same fields
            } else if (functionSelector == IExecutorHelper.executeAmbient.selector) {
                swap.data = ScalingDataLib.newAmbient(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeNative.selector) {
                revert("InputScalingHelper: Can not scale Native swap");
            } else if (functionSelector == IExecutorHelper.executeLighterV2.selector) {
                swap.data = ScalingDataLib.newLighterV2(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeBebop.selector) {
                revert("InputScalingHelper: Can not scale Bebop swap");
            } else if (functionSelector == IExecutorHelper.executeUniV1.selector) {
                swap.data = ScalingDataLib.newUniV1(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeEtherFieETH.selector) {
                swap.data = ScalingDataLib.newEtherFieETH(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeEtherFiWeETH.selector) {
                swap.data = ScalingDataLib.newEtherFiWeETH(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeKelp.selector) {
                swap.data = ScalingDataLib.newKelp(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeEthenaSusde.selector) {
                swap.data = ScalingDataLib.newEthenaSusde(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeRocketPool.selector) {
                swap.data = ScalingDataLib.newRocketPool(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeMakersDAI.selector) {
                swap.data = ScalingDataLib.newMakersDAI(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeRenzo.selector) {
                swap.data = ScalingDataLib.newRenzo(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeWBETH.selector) {
                swap.data = ScalingDataLib.newEtherFieETH(swap.data, oldAmount, newAmount); // same etherfi eETH
            } else if (functionSelector == IExecutorHelper.executeMantleETH.selector) {
                swap.data = ScalingDataLib.newEtherFieETH(swap.data, oldAmount, newAmount); // same etherfi eETH
            } else if (functionSelector == IExecutorHelper.executeFrxETH.selector) {
                swap.data = ScalingDataLib.newFrxETH(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeSfrxETH.selector) {
                swap.data = ScalingDataLib.newSfrxETH(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeSfrxETHConvertor.selector) {
                swap.data = ScalingDataLib.newSfrxETHConvertor(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeSwellETH.selector) {
                swap.data = ScalingDataLib.newEtherFieETH(swap.data, oldAmount, newAmount); // same etherfi eETH
            } else if (functionSelector == IExecutorHelper.executeRswETH.selector) {
                swap.data = ScalingDataLib.newEtherFieETH(swap.data, oldAmount, newAmount); // same etherfi eETH
            } else if (functionSelector == IExecutorHelper.executeStaderETHx.selector) {
                swap.data = ScalingDataLib.newEthenaSusde(swap.data, oldAmount, newAmount); // same ethena susde
            } else if (functionSelector == IExecutorHelper.executeOriginETH.selector) {
                swap.data = ScalingDataLib.newOriginETH(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executePrimeETH.selector) {
                swap.data = ScalingDataLib.newOriginETH(swap.data, oldAmount, newAmount); // same originETH
            } else if (functionSelector == IExecutorHelper.executeMantleUsd.selector) {
                swap.data = ScalingDataLib.newMantleUsd(swap.data, oldAmount, newAmount);
            } else if (functionSelector == IExecutorHelper.executeBedrockUniETH.selector) {
                swap.data = ScalingDataLib.newEtherFieETH(swap.data, oldAmount, newAmount); // same etherfi eETH
            } else if (functionSelector == IExecutorHelper.executeMaiPSM.selector) {
                swap.data = ScalingDataLib.newFrxETH(swap.data, oldAmount, newAmount); // same frxeth
            } else {
                revert("AggregationExecutor: Dex type not supported");
            }
            unchecked {
                ++i;
            }
        }
        return abi.encode(executorDesc);
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
            require(right <= type(uint128).max, "Exceeded type range");
            psData.expectedReturnAmount = right | (left << 128);
            data = abi.encode(psData);
        } else if (data.length == 32) {
            uint256 expectedReturnAmount = abi.decode(data, (uint256));
            uint256 left = uint256(expectedReturnAmount >> 128);
            uint256 right = (uint256(uint128(expectedReturnAmount)) * newAmount) / oldAmount;
            require(right <= type(uint128).max, "Exceeded type range");
            expectedReturnAmount = right | (left << 128);
            data = abi.encode(expectedReturnAmount);
        }
        return data;
    }

    function _flagsChecked(uint256 number, uint256 flag) internal pure returns (bool) {
        return number & flag != 0;
    }
}
