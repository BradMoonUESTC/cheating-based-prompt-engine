// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

library DataTypes {
    struct ReserveData {
        //stores the reserve configuration
        ReserveConfigurationMap configuration;
        //the liquidity index. Expressed in ray
        uint128 liquidityIndex;
        //variable borrow index. Expressed in ray
        uint128 variableBorrowIndex;
        //the current supply rate. Expressed in ray
        uint128 currentLiquidityRate;
        //the current variable borrow rate. Expressed in ray
        uint128 currentVariableBorrowRate;
        uint40 lastUpdateTimestamp;
        //tokens addresses
        address bTokenAddress;
        address debtTokenAddress;
        //address of the interest rate strategy
        address interestRateAddress;
        //the id of the reserve. Represents the position in the list of the active reserves
        uint8 id;
    }

    struct NftData {
        //stores the nft configuration
        NftConfigurationMap configuration;
        //address of the bNFT contract
        address bNftAddress;
        //the id of the nft. Represents the position in the list of the active nfts
        uint8 id;
        uint256 maxSupply;
        uint256 maxTokenId;
    }

    struct ReserveConfigurationMap {
        //bit 0-15: LTV
        //bit 16-31: Liq. threshold
        //bit 32-47: Liq. bonus
        //bit 48-55: Decimals
        //bit 56: Reserve is active
        //bit 57: reserve is frozen
        //bit 58: borrowing is enabled
        //bit 59: stable rate borrowing enabled
        //bit 60-63: reserved
        //bit 64-79: reserve factor
        uint256 data;
    }

    struct NftConfigurationMap {
        //bit 0-15: LTV
        //bit 16-31: Liq. threshold
        //bit 32-47: Liq. bonus
        //bit 56: NFT is active
        //bit 57: NFT is frozen
        uint256 data;
    }

    /**
     * @dev Enum describing the current state of a loan
     * State change flow:
     *  Created -> Active -> Repaid
     *                    -> Auction -> Defaulted
     */
    enum LoanState {
        // We need a default that is not 'Created' - this is the zero value
        None,
        // The loan data is stored, but not initiated yet.
        Created,
        // The loan has been initialized, funds have been delivered to the borrower and the collateral is held.
        Active,
        // The loan is in auction, higest price liquidator will got chance to claim it.
        Auction,
        // The loan has been repaid, and the collateral has been returned to the borrower. This is a terminal state.
        Repaid,
        // The loan was delinquent and collateral claimed by the liquidator. This is a terminal state.
        Defaulted
    }

    struct LoanData {
        //the id of the nft loan
        uint256 loanId;
        //the current state of the loan
        LoanState state;
        //address of borrower
        address borrower;
        //address of nft asset token
        address nftAsset;
        //the id of nft token
        uint256 nftTokenId;
        //address of reserve asset token
        address reserveAsset;
        //scaled borrow amount. Expressed in ray
        uint256 scaledAmount;
        //start time of first bid time
        uint256 bidStartTimestamp;
        //bidder address of higest bid
        address bidderAddress;
        //price of higest bid
        uint256 bidPrice;
        //borrow amount of loan
        uint256 bidBorrowAmount;
        //bidder address of first bid
        address firstBidderAddress;
    }

    struct ExecuteDepositParams {
        address initiator;
        address asset;
        uint256 amount;
        address onBehalfOf;
        uint16 referralCode;
    }

    struct ExecuteWithdrawParams {
        address initiator;
        address asset;
        uint256 amount;
        address to;
    }

    struct ExecuteBorrowParams {
        address initiator;
        address asset;
        uint256 amount;
        address nftAsset;
        uint256 nftTokenId;
        address onBehalfOf;
        uint16 referralCode;
    }

    struct ExecuteBatchBorrowParams {
        address initiator;
        address[] assets;
        uint256[] amounts;
        address[] nftAssets;
        uint256[] nftTokenIds;
        address onBehalfOf;
        uint16 referralCode;
    }

    struct ExecuteRepayParams {
        address initiator;
        address nftAsset;
        uint256 nftTokenId;
        uint256 amount;
    }

    struct ExecuteBatchRepayParams {
        address initiator;
        address[] nftAssets;
        uint256[] nftTokenIds;
        uint256[] amounts;
    }

    struct ExecuteAuctionParams {
        address initiator;
        address nftAsset;
        uint256 nftTokenId;
        uint256 bidPrice;
        address onBehalfOf;
    }

    struct ExecuteRedeemParams {
        address initiator;
        address nftAsset;
        uint256 nftTokenId;
        uint256 amount;
        uint256 bidFine;
    }

    struct ExecuteLiquidateParams {
        address initiator;
        address nftAsset;
        uint256 nftTokenId;
        uint256 amount;
    }

    struct ExecuteLendPoolStates {
        uint256 pauseStartTime;
        uint256 pauseDurationTime;
    }
}
