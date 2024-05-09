// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import {ILendPoolAddressesProvider} from "./ILendPoolAddressesProvider.sol";
import {DataTypes} from "../libraries/types/DataTypes.sol";

interface ILendPool {
    /**
     * @dev Emitted on deposit()
     * @param user The address initiating the deposit
     * @param amount The amount deposited
     * @param reserve The address of the underlying asset of the reserve
     * @param onBehalfOf The beneficiary of the deposit, receiving the bTokens
     * @param referral The referral code used
     **/
    event Deposit(
        address user,
        address indexed reserve,
        uint256 amount,
        address indexed onBehalfOf,
        uint16 indexed referral
    );

    /**
     * @dev Emitted on withdraw()
     * @param user The address initiating the withdrawal, owner of bTokens
     * @param reserve The address of the underlyng asset being withdrawn
     * @param amount The amount to be withdrawn
     * @param to Address that will receive the underlying
     **/
    event Withdraw(
        address indexed user,
        address indexed reserve,
        uint256 amount,
        address indexed to
    );

    /**
     * @dev Emitted on borrow() when loan needs to be opened
     * @param user The address of the user initiating the borrow(), receiving the funds
     * @param reserve The address of the underlying asset being borrowed
     * @param amount The amount borrowed out
     * @param nftAsset The address of the underlying NFT used as collateral
     * @param nftTokenId The token id of the underlying NFT used as collateral
     * @param onBehalfOf The address that will be getting the loan
     * @param referral The referral code used
     **/
    event Borrow(
        address user,
        address indexed reserve,
        uint256 amount,
        address nftAsset,
        uint256 nftTokenId,
        address indexed onBehalfOf,
        uint256 borrowRate,
        uint256 loanId,
        uint16 indexed referral
    );

    /**
     * @dev Emitted on repay()
     * @param user The address of the user initiating the repay(), providing the funds
     * @param reserve The address of the underlying asset of the reserve
     * @param amount The amount repaid
     * @param nftAsset The address of the underlying NFT used as collateral
     * @param nftTokenId The token id of the underlying NFT used as collateral
     * @param borrower The beneficiary of the repayment, getting his debt reduced
     * @param loanId The loan ID of the NFT loans
     **/
    event Repay(
        address user,
        address indexed reserve,
        uint256 amount,
        address indexed nftAsset,
        uint256 nftTokenId,
        address indexed borrower,
        uint256 loanId
    );

    /**
     * @dev Emitted when a borrower's loan is auctioned.
     * @param user The address of the user initiating the auction
     * @param reserve The address of the underlying asset of the reserve
     * @param bidPrice The price of the underlying reserve given by the bidder
     * @param nftAsset The address of the underlying NFT used as collateral
     * @param nftTokenId The token id of the underlying NFT used as collateral
     * @param onBehalfOf The address that will be getting the NFT
     * @param loanId The loan ID of the NFT loans
     **/
    event Auction(
        address user,
        address indexed reserve,
        uint256 bidPrice,
        address indexed nftAsset,
        uint256 nftTokenId,
        address onBehalfOf,
        address indexed borrower,
        uint256 loanId
    );

    /**
     * @dev Emitted on redeem()
     * @param user The address of the user initiating the redeem(), providing the funds
     * @param reserve The address of the underlying asset of the reserve
     * @param borrowAmount The borrow amount repaid
     * @param nftAsset The address of the underlying NFT used as collateral
     * @param nftTokenId The token id of the underlying NFT used as collateral
     * @param loanId The loan ID of the NFT loans
     **/
    event Redeem(
        address user,
        address indexed reserve,
        uint256 borrowAmount,
        uint256 fineAmount,
        address indexed nftAsset,
        uint256 nftTokenId,
        address indexed borrower,
        uint256 loanId
    );

    /**
     * @dev Emitted when a borrower's loan is liquidated.
     * @param user The address of the user initiating the auction
     * @param reserve The address of the underlying asset of the reserve
     * @param repayAmount The amount of reserve repaid by the liquidator
     * @param remainAmount The amount of reserve received by the borrower
     * @param loanId The loan ID of the NFT loans
     **/
    event Liquidate(
        address user,
        address indexed reserve,
        uint256 repayAmount,
        uint256 remainAmount,
        address indexed nftAsset,
        uint256 nftTokenId,
        address indexed borrower,
        uint256 loanId
    );

    /**
     * @dev Emitted when the pause is triggered.
     */
    event Paused();

    /**
     * @dev Emitted when the pause is lifted.
     */
    event Unpaused();

    /**
     * @dev Emitted when the pause time is updated.
     */
    event PausedTimeUpdated(uint256 startTime, uint256 durationTime);

    /**
     * @dev Emitted when the state of a reserve is updated. NOTE: This event is actually declared
     * in the ReserveLogic library and emitted in the updateInterestRates() function. Since the function is internal,
     * the event will actually be fired by the LendPool contract. The event is therefore replicated here so it
     * gets added to the LendPool ABI
     * @param reserve The address of the underlying asset of the reserve
     * @param liquidityRate The new liquidity rate
     * @param variableBorrowRate The new variable borrow rate
     * @param liquidityIndex The new liquidity index
     * @param variableBorrowIndex The new variable borrow index
     **/
    event ReserveDataUpdated(
        address indexed reserve,
        uint256 liquidityRate,
        uint256 variableBorrowRate,
        uint256 liquidityIndex,
        uint256 variableBorrowIndex
    );

    /**
     * @dev Deposits an `amount` of underlying asset into the reserve, receiving in return overlying bTokens.
     * - E.g. User deposits 100 USDC and gets in return 100 bUSDC
     * @param reserve The address of the underlying asset to deposit
     * @param amount The amount to be deposited
     * @param onBehalfOf The address that will receive the bTokens, same as msg.sender if the user
     *   wants to receive them on his own wallet, or a different address if the beneficiary of bTokens
     *   is a different wallet
     * @param referralCode Code used to register the integrator originating the operation, for potential rewards.
     *   0 if the action is executed directly by the user, without any middle-man
     **/
    function deposit(
        address reserve,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    /**
     * @dev Withdraws an `amount` of underlying asset from the reserve, burning the equivalent bTokens owned
     * E.g. User has 100 bUSDC, calls withdraw() and receives 100 USDC, burning the 100 bUSDC
     * @param reserve The address of the underlying asset to withdraw
     * @param amount The underlying amount to be withdrawn
     *   - Send the value type(uint256).max in order to withdraw the whole bToken balance
     * @param to Address that will receive the underlying, same as msg.sender if the user
     *   wants to receive it on his own wallet, or a different address if the beneficiary is a
     *   different wallet
     * @return The final amount withdrawn
     **/
    function withdraw(
        address reserve,
        uint256 amount,
        address to
    ) external returns (uint256);

    /**
     * @dev Allows users to borrow a specific `amount` of the reserve underlying asset, provided that the borrower
     * already deposited enough collateral
     * - E.g. User borrows 100 USDC, receiving the 100 USDC in his wallet
     *   and lock collateral asset in contract
     * @param reserveAsset The address of the underlying asset to borrow
     * @param amount The amount to be borrowed
     * @param nftAsset The address of the underlying NFT used as collateral
     * @param nftTokenId The token ID of the underlying NFT used as collateral
     * @param onBehalfOf Address of the user who will receive the loan. Should be the address of the borrower itself
     * calling the function if he wants to borrow against his own collateral, or the address of the credit delegator
     * if he has been given credit delegation allowance
     * @param referralCode Code used to register the integrator originating the operation, for potential rewards.
     *   0 if the action is executed directly by the user, without any middle-man
     **/
    function borrow(
        address reserveAsset,
        uint256 amount,
        address nftAsset,
        uint256 nftTokenId,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    function batchBorrow(
        address[] calldata assets,
        uint256[] calldata amounts,
        address[] calldata nftAssets,
        uint256[] calldata nftTokenIds,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    /**
     * @notice Repays a borrowed `amount` on a specific reserve, burning the equivalent loan owned
     * - E.g. User repays 100 USDC, burning loan and receives collateral asset
     * @param nftAsset The address of the underlying NFT used as collateral
     * @param nftTokenId The token ID of the underlying NFT used as collateral
     * @param amount The amount to repay
     * @return The final amount repaid, loan is burned or not
     **/
    function repay(
        address nftAsset,
        uint256 nftTokenId,
        uint256 amount
    ) external returns (uint256, bool);

    function batchRepay(
        address[] calldata nftAssets,
        uint256[] calldata nftTokenIds,
        uint256[] calldata amounts
    ) external returns (uint256[] memory, bool[] memory);

    /**
     * @dev Function to auction a non-healthy position collateral-wise
     * - The caller (liquidator) want to buy collateral asset of the user getting liquidated
     * @param nftAsset The address of the underlying NFT used as collateral
     * @param nftTokenId The token ID of the underlying NFT used as collateral
     * @param bidPrice The bid price of the liquidator want to buy the underlying NFT
     * @param onBehalfOf Address of the user who will get the underlying NFT, same as msg.sender if the user
     *   wants to receive them on his own wallet, or a different address if the beneficiary of NFT
     *   is a different wallet
     **/
    function auction(
        address nftAsset,
        uint256 nftTokenId,
        uint256 bidPrice,
        address onBehalfOf
    ) external;

    /**
     * @notice Redeem a NFT loan which state is in Auction
     * - E.g. User repays 100 USDC, burning loan and receives collateral asset
     * @param nftAsset The address of the underlying NFT used as collateral
     * @param nftTokenId The token ID of the underlying NFT used as collateral
     * @param amount The amount to repay the debt
     * @param bidFine The amount of bid fine
     **/
    function redeem(
        address nftAsset,
        uint256 nftTokenId,
        uint256 amount,
        uint256 bidFine
    ) external returns (uint256);

    /**
     * @dev Function to liquidate a non-healthy position collateral-wise
     * - The caller (liquidator) buy collateral asset of the user getting liquidated, and receives
     *   the collateral asset
     * @param nftAsset The address of the underlying NFT used as collateral
     * @param nftTokenId The token ID of the underlying NFT used as collateral
     **/
    function liquidate(
        address nftAsset,
        uint256 nftTokenId,
        uint256 amount
    ) external returns (uint256);

    /**
     * @dev Validates and finalizes an bToken transfer
     * - Only callable by the overlying bToken of the `asset`
     * @param asset The address of the underlying asset of the bToken
     * @param from The user from which the bTokens are transferred
     * @param to The user receiving the bTokens
     * @param amount The amount being transferred/withdrawn
     * @param balanceFromBefore The bToken balance of the `from` user before the transfer
     * @param balanceToBefore The bToken balance of the `to` user before the transfer
     */
    function finalizeTransfer(
        address asset,
        address from,
        address to,
        uint256 amount,
        uint256 balanceFromBefore,
        uint256 balanceToBefore
    ) external view;

    function getReserveConfiguration(
        address asset
    ) external view returns (DataTypes.ReserveConfigurationMap memory);

    function getNftConfiguration(
        address asset
    ) external view returns (DataTypes.NftConfigurationMap memory);

    /**
     * @dev Returns the normalized income normalized income of the reserve
     * @param asset The address of the underlying asset of the reserve
     * @return The reserve's normalized income
     */
    function getReserveNormalizedIncome(
        address asset
    ) external view returns (uint256);

    /**
     * @dev Returns the normalized variable debt per unit of asset
     * @param asset The address of the underlying asset of the reserve
     * @return The reserve normalized variable debt
     */
    function getReserveNormalizedVariableDebt(
        address asset
    ) external view returns (uint256);

    /**
     * @dev Returns the state and configuration of the reserve
     * @param asset The address of the underlying asset of the reserve
     * @return The state of the reserve
     **/
    function getReserveData(
        address asset
    ) external view returns (DataTypes.ReserveData memory);

    function getReservesList() external view returns (address[] memory);

    function getNftData(
        address asset
    ) external view returns (DataTypes.NftData memory);

    /**
     * @dev Returns the loan data of the NFT
     * @param nftAsset The address of the NFT
     * @param reserveAsset The address of the Reserve
     * @return totalCollateralInETH the total collateral in ETH of the NFT
     * @return totalCollateralInReserve the total collateral in Reserve of the NFT
     * @return availableBorrowsInETH the borrowing power in ETH of the NFT
     * @return availableBorrowsInReserve the borrowing power in Reserve of the NFT
     * @return ltv the loan to value of the user
     * @return liquidationThreshold the liquidation threshold of the NFT
     * @return liquidationBonus the liquidation bonus of the NFT
     **/
    function getNftCollateralData(
        address nftAsset,
        address reserveAsset
    )
        external
        view
        returns (
            uint256 totalCollateralInETH,
            uint256 totalCollateralInReserve,
            uint256 availableBorrowsInETH,
            uint256 availableBorrowsInReserve,
            uint256 ltv,
            uint256 liquidationThreshold,
            uint256 liquidationBonus
        );

    /**
     * @dev Returns the debt data of the NFT
     * @param nftAsset The address of the NFT
     * @param nftTokenId The token id of the NFT
     * @return loanId the loan id of the NFT
     * @return reserveAsset the address of the Reserve
     * @return totalCollateral the total power of the NFT
     * @return totalDebt the total debt of the NFT
     * @return availableBorrows the borrowing power left of the NFT
     * @return healthFactor the current health factor of the NFT
     **/
    function getNftDebtData(
        address nftAsset,
        uint256 nftTokenId
    )
        external
        view
        returns (
            uint256 loanId,
            address reserveAsset,
            uint256 totalCollateral,
            uint256 totalDebt,
            uint256 availableBorrows,
            uint256 healthFactor
        );

    /**
     * @dev Returns the auction data of the NFT
     * @param nftAsset The address of the NFT
     * @param nftTokenId The token id of the NFT
     * @return loanId the loan id of the NFT
     * @return bidderAddress the highest bidder address of the loan
     * @return bidPrice the highest bid price in Reserve of the loan
     * @return bidBorrowAmount the borrow amount in Reserve of the loan
     * @return bidFine the penalty fine of the loan
     **/
    function getNftAuctionData(
        address nftAsset,
        uint256 nftTokenId
    )
        external
        view
        returns (
            uint256 loanId,
            address bidderAddress,
            uint256 bidPrice,
            uint256 bidBorrowAmount,
            uint256 bidFine
        );

    function getNftAuctionEndTime(
        address nftAsset,
        uint256 nftTokenId
    )
        external
        view
        returns (
            uint256 loanId,
            uint256 bidStartTimestamp,
            uint256 bidEndTimestamp,
            uint256 redeemEndTimestamp
        );

    function getNftLiquidatePrice(
        address nftAsset,
        uint256 nftTokenId
    ) external view returns (uint256 liquidatePrice, uint256 paybackAmount);

    function getNftsList() external view returns (address[] memory);

    /**
     * @dev Set the _pause state of a reserve
     * - Only callable by the LendPool contract
     * @param val `true` to pause the reserve, `false` to un-pause it
     */
    function setPause(bool val) external;

    function setPausedTime(uint256 startTime, uint256 durationTime) external;

    /**
     * @dev Returns if the LendPool is paused
     */
    function paused() external view returns (bool);

    function getPausedTime() external view returns (uint256, uint256);

    function getAddressesProvider()
        external
        view
        returns (ILendPoolAddressesProvider);

    function initReserve(
        address asset,
        address bTokenAddress,
        address debtTokenAddress,
        address interestRateAddress
    ) external;

    function initNft(address asset, address bNftAddress) external;

    function setReserveInterestRateAddress(
        address asset,
        address rateAddress
    ) external;

    function setReserveConfiguration(
        address asset,
        uint256 configuration
    ) external;

    function setNftConfiguration(address asset, uint256 configuration) external;

    function setNftMaxSupplyAndTokenId(
        address asset,
        uint256 maxSupply,
        uint256 maxTokenId
    ) external;

    function setMaxNumberOfReserves(uint256 val) external;

    function setMaxNumberOfNfts(uint256 val) external;

    function getMaxNumberOfReserves() external view returns (uint256);

    function getMaxNumberOfNfts() external view returns (uint256);
}
