// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

library ContractsAddress {
    /******************
     **** Mainnet ****
     *****************/
    address public constant ETHAddress =
        address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    //https://etherscan.io/token/0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    //https://etherscan.io/token/0xdac17f958d2ee523a2206206994597c13d831ec7
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    //https://etherscan.io/token/0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    //https://etherscan.io/token/0x6b175474e89094c44da98b954eedeac495271d0f
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    /**********************
     **** Arbitrum  One****
     *********************/
    //https://docs.arbitrum.io/for-devs/useful-addresses
    //https://etherscan.io/address/0x72Ce9c846789fdB6fC1f34aC4AD25Dd9ef7031ef

    address public constant ArbitrumOneL1GatewayRouter =
        0x72Ce9c846789fdB6fC1f34aC4AD25Dd9ef7031ef;
    //https://etherscan.io/address/0xd92023E9d9911199a6711321D1277285e6d4e2db
    address public constant ArbitrumOneL1WETHGateway =
        0xd92023E9d9911199a6711321D1277285e6d4e2db;
    //https://etherscan.io/address/0xa3A7B6F88361F48403514059F1F16C8E78d60EeC
    address public constant ArbitrumOneL1ERC20Gateway =
        0xa3A7B6F88361F48403514059F1F16C8E78d60EeC;
    //https://arbiscan.io/address/0x5288c571Fd7aD117beA99bF60FE0846C4E84F933
    address public constant ArbitrumOneL2GatewayRouter =
        0x5288c571Fd7aD117beA99bF60FE0846C4E84F933;
    //https://arbiscan.io/address/0x6c411aD3E74De3E7Bd422b94A27770f5B86C623B
    address public constant ArbitrumOneL2WETHGateway =
        0x6c411aD3E74De3E7Bd422b94A27770f5B86C623B;
    //https://arbiscan.io/address/0x09e9222E96E7B4AE2a407B98d48e330053351EEe
    address public constant ArbitrumOneL2ERC20Gateway =
        0x09e9222E96E7B4AE2a407B98d48e330053351EEe;

    //https://arbiscan.io/address/0x82aF49447D8a07e3bd95BD0d56f35241523fBab1
    address public constant ArbitrumOneWETH =
        0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    /**********************
     **** Arbitrum  Nova***
     *********************/
    //https://docs.arbitrum.io/for-devs/useful-addresses
    //https://etherscan.io/address/0xC840838Bc438d73C16c2f8b22D2Ce3669963cD48
    address public constant ArbitrumNovaL1GatewayRouter =
        0xC840838Bc438d73C16c2f8b22D2Ce3669963cD48;
    //https://etherscan.io/address/0xB2535b988dcE19f9D71dfB22dB6da744aCac21bf
    address public constant ArbitrumNovaL1ERC20Gateway =
        0xB2535b988dcE19f9D71dfB22dB6da744aCac21bf;
    //https://etherscan.io/address/0xE4E2121b479017955Be0b175305B35f312330BaE
    address public constant ArbitrumNovaL1WETHGateway =
        0xE4E2121b479017955Be0b175305B35f312330BaE;
    //https://nova.arbiscan.io/address/0x21903d3F8176b1a0c17E953Cd896610Be9fFDFa8
    address public constant ArbitrumNovaL2GatewayRouter =
        0x21903d3F8176b1a0c17E953Cd896610Be9fFDFa8;
    //https://nova.arbiscan.io/address/0xcF9bAb7e53DDe48A6DC4f286CB14e05298799257
    address public constant ArbitrumNovaL2ERC20Gateway =
        0xcF9bAb7e53DDe48A6DC4f286CB14e05298799257;
    //https://nova.arbiscan.io/address/0x7626841cB6113412F9c88D3ADC720C9FAC88D9eD
    address public constant ArbitrumNovaL2WETHGateway =
        0x7626841cB6113412F9c88D3ADC720C9FAC88D9eD;
    //https://nova.arbiscan.io/address/0x722E8BdD2ce80A4422E880164f2079488e115365
    address public constant ArbitrumNovaWETH =
        0x722E8BdD2ce80A4422E880164f2079488e115365;

    /******************
     ***** Linea ******
     *****************/

    address public constant LineaCustomerBridge =
        0x0000000000000000000000000000000000000001; //TODO
    //https://lineascan.build/token/0xe5d7c2a44ffddf6b295a15c148167daaaf5cf34f
    address public constant LineaWETH =
        0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f;


    /********************
     ***** ZkSync *******
     *******************/
    //https://etherscan.io/address/0x57891966931eb4bb6fb81430e6ce0a03aabde063#readProxyContract
    address public constant ZkSyncL1Bridge =
        0x57891966931Eb4Bb6FB81430E6cE0A03AAbDe063;
    //https://explorer.zksync.io/address/0x11f943b2c77b743ab90f4a0ae7d5a4e7fca3e102#contract
    address public constant ZkSyncL2Bridge =
        0x11f943b2c77b743AB90f4A0Ae7d5A4e7FCA3E102;
    //https://era.zksync.network/token/0x5aea5775959fbc2557cc8789bc1bf90a239d9a91
    address public constant ZkSyncWETH =
        0x5AEa5775959fBC2557Cc8789bC1bf90A239D9a91;

        
    /********************
     ***** Mantle *******
     *******************/
    //https://etherscan.io/address/0x95fC37A27a2f68e3A647CDc081F0A89bb47c3012#code
    address public constant MantleL1Bridge =
        0x95fC37A27a2f68e3A647CDc081F0A89bb47c3012;
    //https://explorer.mantle.xyz/address/0x4200000000000000000000000000000000000010/contracts#address-tabs
    address public constant MantleL2Bridge =
        0x4200000000000000000000000000000000000010;
    //https://explorer.mantle.xyz/token/0xdEAddEaDdeadDEadDEADDEAddEADDEAddead1111/token-transfers
    address public constant MantleETH =
        0xdEAddEaDdeadDEadDEADDEAddEADDEAddead1111;
    
     /********************
     ***** Manta *******
     *******************/
    //https://etherscan.io/address/0x3B95bC951EE0f553ba487327278cAc44f29715E5#writeProxyContract
    address public constant MantaL1Bridge =
        0x3B95bC951EE0f553ba487327278cAc44f29715E5;
    //https://pacific-explorer.manta.network/address/0x4200000000000000000000000000000000000010
    address public constant MantaL2Bridge =
        0x4200000000000000000000000000000000000010;
    


    /*******************
     ** Polygon ZkEVM **
     *******************/
    //https://docs.polygon.technology/zkEVM/architecture/protocol/zkevm-bridge/smart-contracts/

    //https://etherscan.io/address/0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe#readProxyContract
    address public constant PolygonZkEVML1Bridge =
        0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe;
    //https://zkevm.polygonscan.com/address/0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe
    address public constant PolygonZkEVML2Bridge =
        0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe;
    //https://zkevm.polygonscan.com/token/0x4F9A0e7FD2Bf6067db6994CF12E4495Df938E6e9
    address public constant PolygonZkEVMWETH =
        0x4F9A0e7FD2Bf6067db6994CF12E4495Df938E6e9;
    //https://zkevm.polygonscan.com/token/0x1e4a5963abfd975d8c9021ce480b42188849d41d
    address public constant PolygonZkEVMUSDT =
        0x1E4a5963aBFD975d8c9021ce480b42188849D41d;
    //https://zkevm.polygonscan.com/token/0xa8ce8aee21bc2a48a5ef670afcc9274c7bbbc035
    address public constant PolygonZkEVMUSDC =
        0xA8CE8aee21bC2A48a5EF670afCc9274C7bbbC035;
    //https://zkevm.polygonscan.com/token/0xc5015b9d9161dca7e18e32f6f25c4ad850731fd4
    address public constant PolygonZkEVMDAI =
        0xC5015b9d9161Dca7e18e32f6f25C4aD850731Fd4;

    /******************
     ***** Scroll *****
     *****************/
    //https://docs.scroll.io/en/developers/scroll-contracts/

    //https://etherscan.io/address/0xD8A791fE2bE73eb6E6cF1eb0cb3F36adC9B3F8f9
    address public constant ScrollL1StandardERC20Bridge =
        0xD8A791fE2bE73eb6E6cF1eb0cb3F36adC9B3F8f9;
    //https://etherscan.io/address/0x7AC440cAe8EB6328de4fA621163a792c1EA9D4fE
    address public constant ScrollL1StandardWETHBridge =
        0x7AC440cAe8EB6328de4fA621163a792c1EA9D4fE;
    //https://scrollscan.com/address/0xE2b4795039517653c5Ae8C2A9BFdd783b48f447A
    address public constant ScrollL2StandardERC20Bridge =
        0xE2b4795039517653c5Ae8C2A9BFdd783b48f447A;
    //https://scrollscan.com/address/0x7003E7B7186f0E6601203b99F7B8DECBfA391cf9
    address public constant ScrollL2StandardWETHBridge =
        0x7003E7B7186f0E6601203b99F7B8DECBfA391cf9;
    //https://etherscan.io/address/0x7F2b8C31F88B6006c382775eea88297Ec1e3E905
    address public constant ScrollL1StandardETHBridge =
        0x7F2b8C31F88B6006c382775eea88297Ec1e3E905;
    //https://scrollscan.com/address/0x6EA73e05AdC79974B931123675ea8F78FfdacDF0
    address public constant ScrollL2StandardETHBridge =
        0x6EA73e05AdC79974B931123675ea8F78FfdacDF0;
    //https://scrollscan.com/token/0x5300000000000000000000000000000000000004
    address public constant ScrollL1MessageQueue =
        0x0d7E906BD9cAFa154b048cFa766Cc1E54E39AF9B;

    //https://scrollscan.com/token/0xf55bec9cafdbe8730f096aa55dad6d22d44099df
    address public constant ScrollUSDT =
        0xf55BEC9cafDbE8730f096Aa55dad6D22d44099Df;
    //https://scrollscan.com/token/0x06efdbff2a14a7c8e15944d1f4a48f9f95f663a4
    address public constant ScrollUSDC =
        0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4;
    //https://scrollscan.com/token/0xca77eb3fefe3725dc33bccb54edefc3d9f764f97
    address public constant ScrollDAI =
        0xcA77eB3fEFe3725Dc33bccB54eDEFc3D9f764f97;
    //https://scrollscan.com/token/0x5300000000000000000000000000000000000004
    address public constant ScrollWETH =
        0x5300000000000000000000000000000000000004;

    /******************
     ***** Optimism ***
     *****************/

    //https://etherscan.io/address/0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1#readProxyContract
    address public constant OptimismL1StandardBridge =
        0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1;
    // https://optimistic.etherscan.io/address/0xc0d3c0d3c0d3c0d3c0d3c0d3c0d3c0d3c0d30010#code#F2#L179
    address public constant OptimismL2StandardBridge =
        0x4200000000000000000000000000000000000010;

    address public constant OP_LEGACY_ERC20_ETH =
        0xDeadDeAddeAddEAddeadDEaDDEAdDeaDDeAD0000;

    //https://optimistic.etherscan.io/token/0x4200000000000000000000000000000000000006
    address public constant OptimismWETH =
        0x4200000000000000000000000000000000000006;

    //https://optimistic.etherscan.io/token/0x94b008aa00579c1307b0ef2c499ad98a8ce58e58
    address public constant OptimismUSDT =
        0x94b008aA00579c1307B0EF2c499aD98a8ce58e58;
    //https://optimistic.etherscan.io/token/0x0b2c639c533813f4aa9d7837caf62653d097ff85
    address public constant OptimismUSDC =
        0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
    //https://optimistic.etherscan.io/token/0xda10009cbd5d07dd0cecc66161fc93d7c9000da1
    address public constant OptimismDAI =
        0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;


    /*******************
     ** ZkFAIR **
     *******************/
    //https://docs.zkfair.io/resources/zkfair-contracts

    //https://etherscan.io/address/0x9cb4706e20a18e59a48ffa7616d700a3891e1861#readProxyContract
    address public constant ZKFairL1Bridge =
        0x9cb4706e20A18E59a48ffa7616d700A3891e1861;
    //https://scan.zkfair.io/address/0x2c4813276869D93AFdaB4dd2B01Cd670342da194
    address public constant ZKFairL2Bridge =
        0x2c4813276869D93AFdaB4dd2B01Cd670342da194;
    //https://scan.zkfair.io/token/0x4b21b980d0Dc7D3C0C6175b0A412694F3A1c7c6b?tab=contract
    address public constant ZKFairETH =
        0x4b21b980d0Dc7D3C0C6175b0A412694F3A1c7c6b;
    //https://scan.zkfair.io/token/0x3f97bf3Cd76B5cA9D4A4E9cD8a73C24E32d6C193
    address public constant ZKFairUSDT =
        0x3f97bf3Cd76B5cA9D4A4E9cD8a73C24E32d6C193;
    //https://scan.zkfair.io/token/0xa9f4EEb30dC48D4Ef77310A2108816C80457cF6F
    address public constant ZKFairDAI =
        0xa9f4EEb30dC48D4Ef77310A2108816C80457cF6F;
    // ZKFair does not support USDC and WETH

        /***************************
     ***** Base  *****
     **************************/
     //https://https://etherscan.io/address/0x3154Cf16ccdb4C6d922629664174b904d80F2C35
    address public constant BaseL1StandardBridge =
        0x3154Cf16ccdb4C6d922629664174b904d80F2C35;
    //https://basescan.org/address/0x4200000000000000000000000000000000000006#code
    address public constant BaseWETH =
        0x4200000000000000000000000000000000000006;
    //https://basescan.org/address/0x4200000000000000000000000000000000000010
    address public constant BaseL2StandardBridge =
        0x4200000000000000000000000000000000000010;
    address public constant BASE_LEGACY_ERC20_ETH =
       0xDeadDeAddeAddEAddeadDEaDDEAdDeaDDeAD0000;
}