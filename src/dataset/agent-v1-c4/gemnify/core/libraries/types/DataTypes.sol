// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

library DataTypes {
    struct Position {
        uint256 size;
        uint256 collateral;
        uint256 averagePrice;
        uint256 entryBorrowingRate;
        uint256 fundingFeeAmountPerSize;
        uint256 claimableFundingAmountPerSize;
        uint256 reserveAmount;
        int256 realisedPnl;
        uint256 lastIncreasedTime;
    }

    struct SetFeesParams {
        uint256 taxBasisPoints;
        uint256 stableTaxBasisPoints;
        uint256 mintBurnFeeBasisPoints;
        uint256 swapFeeBasisPoints;
        uint256 stableSwapFeeBasisPoints;
        uint256 marginFeeBasisPoints;
        uint256 liquidationFeeEth;
        uint256 minProfitTime;
        bool hasDynamicFees;
    }

    struct SetAddressesParams {
        address weth;
        address router;
        address priceFeed;
        address ethg;
        address bendOracle;
        address refinance;
        address stargateRouter;
    }

    struct UpdateCumulativeBorrowingRateParams {
        address collateralToken;
        address indexToken;
        uint256 borrowingInterval;
        uint256 borrowingRateFactor;
        uint256 collateralTokenPoolAmount;
        uint256 collateralTokenReservedAmount;
    }

    struct SwapParams {
        bool isSwapEnabled;
        address tokenIn;
        address tokenOut;
        address receiver;
        bool isStableSwap;
        address ethg;
        address priceFeed;
        uint256 totalTokenWeights;
    }

    struct IncreasePositionParams {
        address account;
        address collateralToken;
        address indexToken;
        uint256 sizeDelta;
        bool isLong;
    }

    struct DecreasePositionParams {
        address account;
        address collateralToken;
        address indexToken;
        uint256 collateralDelta;
        uint256 sizeDelta;
        bool isLong;
        address receiver;
    }

    struct LiquidatePositionParams {
        address account;
        address collateralToken;
        address indexToken;
        bool isLong;
        address feeReceiver;
    }

    struct NftStatus {
        uint256 tokenId;
        bool isRefinanced;
    }

    struct NftInfo {
        address certiNft; // an NFT certificate proof-of-ownership, which can only be used to redeem their deposited NFT!
        uint256 nftLtv;
    }

    struct SetTokenConfigParams {
        address token;
        uint256 tokenDecimals;
        uint256 tokenWeight;
        uint256 minProfitBps;
        uint256 maxEthgAmount;
        bool isStable;
        bool isShortable;
        bool isNft;
    }

    // vault storage
    struct AddressStorage {
        address weth;
        address router;
        address priceFeed;
        address ethg;
        address bendOracle;
        address refinance;
        address stargateRouter;
    }

    struct TokenConfigSotrage {
        uint256 whitelistedTokenCount;
        uint256 totalTokenWeights;
        address[] allWhitelistedTokens;
        mapping(address => bool) whitelistedTokens;
        mapping(address => uint256) tokenDecimals;
        mapping(address => uint256) tokenWeights;
        mapping(address => uint256) minProfitBasisPoints;
        mapping(address => uint256) maxEthgAmounts;
        mapping(address => bool) stableTokens;
        mapping(address => bool) shortableTokens;
        mapping(address => bool) nftTokens;
    }

    struct FeeStorage {
        uint256 taxBasisPoints;
        uint256 stableTaxBasisPoints;
        uint256 mintBurnFeeBasisPoints;
        uint256 swapFeeBasisPoints;
        uint256 stableSwapFeeBasisPoints;
        uint256 marginFeeBasisPoints;
        uint256 liquidationFeeEth;
        uint256 minProfitTime;
        bool hasDynamicFees;
        mapping(address => uint256) feeReserves;
        // borrowing fee
        uint256 borrowingInterval;
        uint256 borrowingRateFactor;
        uint256 stableBorrowingRateFactor;
        mapping(address => uint256) cumulativeBorrowingRates;
        mapping(address => uint256) lastBorrowingTimes;
        // funding fee
        mapping(address => uint256) fundingFactors;
        mapping(address => uint256) fundingExponentFactors;
        mapping(address => uint256) lastFundingTimes;
        mapping(address => mapping(bool => uint256)) fundingFeeAmountPerSizes; // indexToken -> isLong -> fundingFeeAmountPerSize
        mapping(address => mapping(bool => uint256)) claimableFundingAmountPerSizes; // indexToken -> isLong -> fundingFeeAmountPerSize
        mapping(address => mapping(address => uint256)) claimableFundingAmount; // user's account -> long token or short token address -> claimableFundingAmount
        // price impact fee
        mapping(address => uint256) swapImpactExponentFactors;
        mapping(address => mapping(bool => uint256)) swapImpactFactors; // token -> isPositive -> impactFactor
        mapping(address => uint256) swapImpactPoolAmounts;
        mapping(address => uint256) positionImpactExponents;
        mapping(address => mapping(bool => uint256)) positionImpactFactors; // token -> isPositive -> impactFactor
        mapping(address => uint256) positionImpactPoolAmounts;
    }

    struct PermissionStorage {
        bool isSwapEnabled;
        bool isLeverageEnabled;
        bool inManagerMode;
        bool inPrivateLiquidationMode;
        mapping(address => mapping(address => bool)) approvedRouters;
        mapping(address => bool) isLiquidator;
        mapping(address => bool) isManager;
        mapping(address => bool) isSwaper;
    }

    struct NftStorage {
        address[] nftUsers;
        mapping(address => NftInfo) nftInfos;
        mapping(address => mapping(address => NftStatus[])) nftStatus;
    }

    struct PositionStorage {
        uint256 maxLeverage; // 50x
        uint256 maxGasPrice;
        mapping(address => uint256) tokenBalances;
        mapping(address => uint256) ethgAmounts;
        mapping(address => uint256) poolAmounts;
        mapping(address => uint256) reservedAmounts;
        mapping(address => uint256) bufferAmounts;
        mapping(address => uint256) guaranteedEth;
        mapping(bytes32 => Position) positions;
        mapping(address => uint256) globalShortSizes;
        mapping(address => uint256) globalShortAveragePrices;
        mapping(address => uint256) maxGlobalShortSizes;
    }

    // tokenInfo
    struct TokenInfo {
        uint256 tokenDecimal;
        bool isWhitelistedToken;
        bool isStableToken;
        bool isNftToken;
    }

    // funding fee
    // @param fundingFeeAmount the position's funding fee amount
    // @param claimableAmount the negative funding fee that is claimable
    // @param latestFundingAmountPerSize the latest funding
    // amount per size for the market
    struct PositionFundingFees {
        uint256 fundingFeeAmount;
        uint256 claimableAmount;
        uint256 latestFundingFeeAmountPerSize;
        uint256 latestClaimableFundingAmountPerSize;
    }
}
