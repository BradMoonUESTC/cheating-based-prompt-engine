// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IExecutorHelper} from "../interfaces/IExecutorHelper.sol";

library ScalingDataLib {
    function newUniSwap(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        IExecutorHelper.UniSwap memory uniSwap = abi.decode(data, (IExecutorHelper.UniSwap));
        uniSwap.collectAmount = (uniSwap.collectAmount * newAmount) / oldAmount;
        return abi.encode(uniSwap);
    }

    function newStableSwap(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.StableSwap memory stableSwap = abi.decode(data, (IExecutorHelper.StableSwap));
        stableSwap.dx = (stableSwap.dx * newAmount) / oldAmount;
        return abi.encode(stableSwap);
    }

    function newCurveSwap(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.CurveSwap memory curveSwap = abi.decode(data, (IExecutorHelper.CurveSwap));
        curveSwap.dx = (curveSwap.dx * newAmount) / oldAmount;
        return abi.encode(curveSwap);
    }

    function newKyberDMM(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        IExecutorHelper.UniSwap memory kyberDMMSwap = abi.decode(data, (IExecutorHelper.UniSwap));
        kyberDMMSwap.collectAmount = (kyberDMMSwap.collectAmount * newAmount) / oldAmount;
        return abi.encode(kyberDMMSwap);
    }

    function newUniV3ProMM(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.UniswapV3KSElastic memory uniSwapV3ProMM = abi.decode(
            data,
            (IExecutorHelper.UniswapV3KSElastic)
        );
        uniSwapV3ProMM.swapAmount = (uniSwapV3ProMM.swapAmount * newAmount) / oldAmount;

        return abi.encode(uniSwapV3ProMM);
    }

    function newBalancerV2(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.BalancerV2 memory balancerV2 = abi.decode(data, (IExecutorHelper.BalancerV2));
        balancerV2.amount = (balancerV2.amount * newAmount) / oldAmount;
        return abi.encode(balancerV2);
    }

    function newDODO(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        IExecutorHelper.DODO memory dodo = abi.decode(data, (IExecutorHelper.DODO));
        dodo.amount = (dodo.amount * newAmount) / oldAmount;
        return abi.encode(dodo);
    }

    function newVelodrome(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.UniSwap memory velodrome = abi.decode(data, (IExecutorHelper.UniSwap));
        velodrome.collectAmount = (velodrome.collectAmount * newAmount) / oldAmount;
        return abi.encode(velodrome);
    }

    function newGMX(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        IExecutorHelper.GMX memory gmx = abi.decode(data, (IExecutorHelper.GMX));
        gmx.amount = (gmx.amount * newAmount) / oldAmount;
        return abi.encode(gmx);
    }

    function newSynthetix(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.Synthetix memory synthetix = abi.decode(data, (IExecutorHelper.Synthetix));
        synthetix.sourceAmount = (synthetix.sourceAmount * newAmount) / oldAmount;
        return abi.encode(synthetix);
    }

    function newCamelot(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        IExecutorHelper.UniSwap memory camelot = abi.decode(data, (IExecutorHelper.UniSwap));
        camelot.collectAmount = (camelot.collectAmount * newAmount) / oldAmount;
        return abi.encode(camelot);
    }

    function newPlatypus(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        IExecutorHelper.Platypus memory platypus = abi.decode(data, (IExecutorHelper.Platypus));
        platypus.collectAmount = (platypus.collectAmount * newAmount) / oldAmount;
        return abi.encode(platypus);
    }

    function newWrappedstETHSwap(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.WSTETH memory wstEthData = abi.decode(data, (IExecutorHelper.WSTETH));
        wstEthData.amount = (wstEthData.amount * newAmount) / oldAmount;
        return abi.encode(wstEthData);
    }

    function newPSM(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        IExecutorHelper.PSM memory psm = abi.decode(data, (IExecutorHelper.PSM));
        psm.amountIn = (psm.amountIn * newAmount) / oldAmount;
        return abi.encode(psm);
    }

    function newFrax(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        IExecutorHelper.UniSwap memory frax = abi.decode(data, (IExecutorHelper.UniSwap));
        frax.collectAmount = (frax.collectAmount * newAmount) / oldAmount;
        return abi.encode(frax);
    }

    function newStETHSwap(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        uint256 amount = abi.decode(data, (uint256));
        amount = (amount * newAmount) / oldAmount;
        return abi.encode(amount);
    }

    function newMaverick(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        IExecutorHelper.Maverick memory maverick = abi.decode(data, (IExecutorHelper.Maverick));
        maverick.swapAmount = (maverick.swapAmount * newAmount) / oldAmount;
        return abi.encode(maverick);
    }

    function newSyncSwap(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        IExecutorHelper.SyncSwap memory syncSwap = abi.decode(data, (IExecutorHelper.SyncSwap));
        syncSwap.collectAmount = (syncSwap.collectAmount * newAmount) / oldAmount;
        return abi.encode(syncSwap);
    }

    function newAlgebraV1(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.AlgebraV1 memory algebraV1Swap = abi.decode(data, (IExecutorHelper.AlgebraV1));
        algebraV1Swap.swapAmount = (algebraV1Swap.swapAmount * newAmount) / oldAmount;
        return abi.encode(algebraV1Swap);
    }

    function newBalancerBatch(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.BalancerBatch memory balancerBatch = abi.decode(data, (IExecutorHelper.BalancerBatch));
        balancerBatch.amountIn = (balancerBatch.amountIn * newAmount) / oldAmount;
        return abi.encode(balancerBatch);
    }

    function newMantis(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        IExecutorHelper.Mantis memory mantis = abi.decode(data, (IExecutorHelper.Mantis));
        mantis.amount = (mantis.amount * newAmount) / oldAmount;
        return abi.encode(mantis);
    }

    function newIziSwap(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        IExecutorHelper.IziSwap memory iZi = abi.decode(data, (IExecutorHelper.IziSwap));
        iZi.swapAmount = (iZi.swapAmount * newAmount) / oldAmount;
        return abi.encode(iZi);
    }

    function newTraderJoeV2(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.TraderJoeV2 memory traderJoe = abi.decode(data, (IExecutorHelper.TraderJoeV2));

        // traderJoe.collectAmount; // most significant 1 bit is to determine whether pool is v2.1, else v2.0
        traderJoe.collectAmount =
            (traderJoe.collectAmount & (1 << 255)) |
            ((uint256((traderJoe.collectAmount << 1) >> 1) * newAmount) / oldAmount);
        return abi.encode(traderJoe);
    }

    function newLevelFiV2(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.LevelFiV2 memory levelFiV2 = abi.decode(data, (IExecutorHelper.LevelFiV2));
        levelFiV2.amountIn = (levelFiV2.amountIn * newAmount) / oldAmount;
        return abi.encode(levelFiV2);
    }

    function newGMXGLP(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        IExecutorHelper.GMXGLP memory swapData = abi.decode(data, (IExecutorHelper.GMXGLP));
        swapData.swapAmount = (swapData.swapAmount * newAmount) / oldAmount;
        return abi.encode(swapData);
    }

    function newVooi(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        IExecutorHelper.Vooi memory vooi = abi.decode(data, (IExecutorHelper.Vooi));
        vooi.fromAmount = (vooi.fromAmount * newAmount) / oldAmount;
        return abi.encode(vooi);
    }

    function newVelocoreV2(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.VelocoreV2 memory velocorev2 = abi.decode(data, (IExecutorHelper.VelocoreV2));
        velocorev2.amount = (velocorev2.amount * newAmount) / oldAmount;
        return abi.encode(velocorev2);
    }

    function newMaticMigrate(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.MaticMigrate memory maticMigrate = abi.decode(data, (IExecutorHelper.MaticMigrate));
        maticMigrate.amount = (maticMigrate.amount * newAmount) / oldAmount;
        return abi.encode(maticMigrate);
    }

    function newKokonut(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        IExecutorHelper.Kokonut memory kokonut = abi.decode(data, (IExecutorHelper.Kokonut));
        kokonut.dx = (kokonut.dx * newAmount) / oldAmount;
        return abi.encode(kokonut);
    }

    function newBalancerV1(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.BalancerV1 memory balancerV1 = abi.decode(data, (IExecutorHelper.BalancerV1));
        balancerV1.amount = (balancerV1.amount * newAmount) / oldAmount;
        return abi.encode(balancerV1);
    }

    function newArbswapStable(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.ArbswapStable memory arbswapStable = abi.decode(data, (IExecutorHelper.ArbswapStable));
        arbswapStable.dx = (arbswapStable.dx * newAmount) / oldAmount;
        return abi.encode(arbswapStable);
    }

    function newBancorV2(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        IExecutorHelper.BancorV2 memory bancorV2 = abi.decode(data, (IExecutorHelper.BancorV2));
        bancorV2.amount = (bancorV2.amount * newAmount) / oldAmount;
        return abi.encode(bancorV2);
    }

    function newAmbient(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        IExecutorHelper.Ambient memory ambient = abi.decode(data, (IExecutorHelper.Ambient));
        ambient.qty = uint128((uint256(ambient.qty) * newAmount) / oldAmount);
        return abi.encode(ambient);
    }

    function newLighterV2(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.LighterV2 memory structData = abi.decode(data, (IExecutorHelper.LighterV2));
        structData.amount = uint128((uint256(structData.amount) * newAmount) / oldAmount);
        return abi.encode(structData);
    }

    function newUniV1(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        IExecutorHelper.UniV1 memory structData = abi.decode(data, (IExecutorHelper.UniV1));
        structData.amount = uint128((uint256(structData.amount) * newAmount) / oldAmount);
        return abi.encode(structData);
    }

    function newEtherFieETH(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        uint256 depositAmount = abi.decode(data, (uint256));
        depositAmount = uint128((depositAmount * newAmount) / oldAmount);
        return abi.encode(depositAmount);
    }

    function newEtherFiWeETH(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.EtherFiWeETH memory structData = abi.decode(data, (IExecutorHelper.EtherFiWeETH));
        structData.amount = uint128((uint256(structData.amount) * newAmount) / oldAmount);
        return abi.encode(structData);
    }

    function newKelp(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        IExecutorHelper.Kelp memory structData = abi.decode(data, (IExecutorHelper.Kelp));
        structData.amount = uint128((uint256(structData.amount) * newAmount) / oldAmount);
        return abi.encode(structData);
    }

    function newEthenaSusde(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.EthenaSusde memory structData = abi.decode(data, (IExecutorHelper.EthenaSusde));
        structData.amount = uint128((uint256(structData.amount) * newAmount) / oldAmount);
        return abi.encode(structData);
    }

    function newRocketPool(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.RocketPool memory structData = abi.decode(data, (IExecutorHelper.RocketPool));

        uint128 _amount = uint128((uint256(uint128(structData.isDepositAndAmount)) * newAmount) / oldAmount);

        bool _isDeposit = (structData.isDepositAndAmount >> 255) == 1;

        // reset and create new variable for isDeposit and amount
        structData.isDepositAndAmount = 0;
        structData.isDepositAndAmount |= uint256(uint128(_amount));
        structData.isDepositAndAmount |= uint256(_isDeposit ? 1 : 0) << 255;

        return abi.encode(structData);
    }

    function newMakersDAI(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.MakersDAI memory structData = abi.decode(data, (IExecutorHelper.MakersDAI));
        uint128 _amount = uint128((uint256(uint128(structData.isRedeemAndAmount)) * newAmount) / oldAmount);

        bool _isRedeem = (structData.isRedeemAndAmount >> 255) == 1;

        // reset and create new variable for isRedeem and amount
        structData.isRedeemAndAmount = 0;
        structData.isRedeemAndAmount |= uint256(uint128(_amount));
        structData.isRedeemAndAmount |= uint256(_isRedeem ? 1 : 0) << 255;

        return abi.encode(structData);
    }

    function newRenzo(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        IExecutorHelper.Renzo memory structData = abi.decode(data, (IExecutorHelper.Renzo));
        structData.amount = uint128((uint256(structData.amount) * newAmount) / oldAmount);
        return abi.encode(structData);
    }

    function newFrxETH(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        IExecutorHelper.FrxETH memory structData = abi.decode(data, (IExecutorHelper.FrxETH));
        structData.amount = uint128((uint256(structData.amount) * newAmount) / oldAmount);
        return abi.encode(structData);
    }

    function newSfrxETH(bytes memory data, uint256 oldAmount, uint256 newAmount) internal pure returns (bytes memory) {
        IExecutorHelper.SfrxETH memory structData = abi.decode(data, (IExecutorHelper.SfrxETH));
        structData.amount = uint128((uint256(structData.amount) * newAmount) / oldAmount);
        return abi.encode(structData);
    }

    function newSfrxETHConvertor(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.SfrxETHConvertor memory structData = abi.decode(data, (IExecutorHelper.SfrxETHConvertor));

        uint128 _amount = uint128((uint256(uint128(structData.isDepositAndAmount)) * newAmount) / oldAmount);

        bool _isDeposit = (structData.isDepositAndAmount >> 255) == 1;

        // reset and create new variable for isDeposit and amount
        structData.isDepositAndAmount = 0;
        structData.isDepositAndAmount |= uint256(uint128(_amount));
        structData.isDepositAndAmount |= uint256(_isDeposit ? 1 : 0) << 255;

        return abi.encode(structData);
    }

    function newOriginETH(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        IExecutorHelper.OriginETH memory structData = abi.decode(data, (IExecutorHelper.OriginETH));
        structData.amount = uint128((uint256(structData.amount) * newAmount) / oldAmount);
        return abi.encode(structData);
    }

    function newMantleUsd(
        bytes memory data,
        uint256 oldAmount,
        uint256 newAmount
    ) internal pure returns (bytes memory) {
        uint256 isWrapAndAmount = abi.decode(data, (uint256));

        uint128 _amount = uint128((uint256(uint128(isWrapAndAmount)) * newAmount) / oldAmount);

        bool _isWrap = (isWrapAndAmount >> 255) == 1;

        // reset and create new variable for isWrap and amount
        isWrapAndAmount = 0;
        isWrapAndAmount |= uint256(uint128(_amount));
        isWrapAndAmount |= uint256(_isWrap ? 1 : 0) << 255;

        return abi.encode(isWrapAndAmount);
    }
}
