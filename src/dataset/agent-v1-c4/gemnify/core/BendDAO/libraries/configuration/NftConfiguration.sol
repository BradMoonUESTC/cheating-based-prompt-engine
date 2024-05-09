// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import {Errors} from "../helpers/Errors.sol";
import {DataTypes} from "../types/DataTypes.sol";

/**
 * @title NftConfiguration library
 * @author Bend
 * @notice Implements the bitmap logic to handle the NFT configuration
 */
library NftConfiguration {
    uint256 constant LTV_MASK =                   0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000; // prettier-ignore
    uint256 constant LIQUIDATION_THRESHOLD_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFF; // prettier-ignore
    uint256 constant LIQUIDATION_BONUS_MASK =     0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFFFFFF; // prettier-ignore
    uint256 constant ACTIVE_MASK =                0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFFFFFFFFFF; // prettier-ignore
    uint256 constant FROZEN_MASK =                0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFDFFFFFFFFFFFFFF; // prettier-ignore
    uint256 constant REDEEM_DURATION_MASK =       0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00FFFFFFFFFFFFFFFF; // prettier-ignore
    uint256 constant AUCTION_DURATION_MASK =      0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00FFFFFFFFFFFFFFFFFF; // prettier-ignore
    uint256 constant REDEEM_FINE_MASK =           0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFFFFFFFFFFFFFFFFFF; // prettier-ignore
    uint256 constant REDEEM_THRESHOLD_MASK =      0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFFFFFFFFFFFFFFFFFFFFFF; // prettier-ignore
    uint256 constant MIN_BIDFINE_MASK      =      0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFFFFFFFFFFFFFFFFFFFFFFFFFF; // prettier-ignore

    /// @dev For the LTV, the start bit is 0 (up to 15), hence no bitshifting is needed
    uint256 constant LIQUIDATION_THRESHOLD_START_BIT_POSITION = 16;
    uint256 constant LIQUIDATION_BONUS_START_BIT_POSITION = 32;
    uint256 constant IS_ACTIVE_START_BIT_POSITION = 56;
    uint256 constant IS_FROZEN_START_BIT_POSITION = 57;
    uint256 constant REDEEM_DURATION_START_BIT_POSITION = 64;
    uint256 constant AUCTION_DURATION_START_BIT_POSITION = 72;
    uint256 constant REDEEM_FINE_START_BIT_POSITION = 80;
    uint256 constant REDEEM_THRESHOLD_START_BIT_POSITION = 96;
    uint256 constant MIN_BIDFINE_START_BIT_POSITION = 112;

    uint256 constant MAX_VALID_LTV = 65535;
    uint256 constant MAX_VALID_LIQUIDATION_THRESHOLD = 65535;
    uint256 constant MAX_VALID_LIQUIDATION_BONUS = 65535;
    uint256 constant MAX_VALID_REDEEM_DURATION = 255;
    uint256 constant MAX_VALID_AUCTION_DURATION = 255;
    uint256 constant MAX_VALID_REDEEM_FINE = 65535;
    uint256 constant MAX_VALID_REDEEM_THRESHOLD = 65535;
    uint256 constant MAX_VALID_MIN_BIDFINE = 65535;

    /**
     * @dev Sets the Loan to Value of the NFT
     * @param self The NFT configuration
     * @param ltv the new ltv
     **/
    function setLtv(
        DataTypes.NftConfigurationMap memory self,
        uint256 ltv
    ) internal pure {
        require(ltv <= MAX_VALID_LTV, Errors.RC_INVALID_LTV);

        self.data = (self.data & LTV_MASK) | ltv;
    }

    /**
     * @dev Gets the Loan to Value of the NFT
     * @param self The NFT configuration
     * @return The loan to value
     **/
    function getLtv(
        DataTypes.NftConfigurationMap storage self
    ) internal view returns (uint256) {
        return self.data & ~LTV_MASK;
    }

    /**
     * @dev Sets the liquidation threshold of the NFT
     * @param self The NFT configuration
     * @param threshold The new liquidation threshold
     **/
    function setLiquidationThreshold(
        DataTypes.NftConfigurationMap memory self,
        uint256 threshold
    ) internal pure {
        require(
            threshold <= MAX_VALID_LIQUIDATION_THRESHOLD,
            Errors.RC_INVALID_LIQ_THRESHOLD
        );

        self.data =
            (self.data & LIQUIDATION_THRESHOLD_MASK) |
            (threshold << LIQUIDATION_THRESHOLD_START_BIT_POSITION);
    }

    /**
     * @dev Gets the liquidation threshold of the NFT
     * @param self The NFT configuration
     * @return The liquidation threshold
     **/
    function getLiquidationThreshold(
        DataTypes.NftConfigurationMap storage self
    ) internal view returns (uint256) {
        return
            (self.data & ~LIQUIDATION_THRESHOLD_MASK) >>
            LIQUIDATION_THRESHOLD_START_BIT_POSITION;
    }

    /**
     * @dev Sets the liquidation bonus of the NFT
     * @param self The NFT configuration
     * @param bonus The new liquidation bonus
     **/
    function setLiquidationBonus(
        DataTypes.NftConfigurationMap memory self,
        uint256 bonus
    ) internal pure {
        require(
            bonus <= MAX_VALID_LIQUIDATION_BONUS,
            Errors.RC_INVALID_LIQ_BONUS
        );

        self.data =
            (self.data & LIQUIDATION_BONUS_MASK) |
            (bonus << LIQUIDATION_BONUS_START_BIT_POSITION);
    }

    /**
     * @dev Gets the liquidation bonus of the NFT
     * @param self The NFT configuration
     * @return The liquidation bonus
     **/
    function getLiquidationBonus(
        DataTypes.NftConfigurationMap storage self
    ) internal view returns (uint256) {
        return
            (self.data & ~LIQUIDATION_BONUS_MASK) >>
            LIQUIDATION_BONUS_START_BIT_POSITION;
    }

    /**
     * @dev Sets the active state of the NFT
     * @param self The NFT configuration
     * @param active The active state
     **/
    function setActive(
        DataTypes.NftConfigurationMap memory self,
        bool active
    ) internal pure {
        self.data =
            (self.data & ACTIVE_MASK) |
            (uint256(active ? 1 : 0) << IS_ACTIVE_START_BIT_POSITION);
    }

    /**
     * @dev Gets the active state of the NFT
     * @param self The NFT configuration
     * @return The active state
     **/
    function getActive(
        DataTypes.NftConfigurationMap storage self
    ) internal view returns (bool) {
        return (self.data & ~ACTIVE_MASK) != 0;
    }

    /**
     * @dev Sets the frozen state of the NFT
     * @param self The NFT configuration
     * @param frozen The frozen state
     **/
    function setFrozen(
        DataTypes.NftConfigurationMap memory self,
        bool frozen
    ) internal pure {
        self.data =
            (self.data & FROZEN_MASK) |
            (uint256(frozen ? 1 : 0) << IS_FROZEN_START_BIT_POSITION);
    }

    /**
     * @dev Gets the frozen state of the NFT
     * @param self The NFT configuration
     * @return The frozen state
     **/
    function getFrozen(
        DataTypes.NftConfigurationMap storage self
    ) internal view returns (bool) {
        return (self.data & ~FROZEN_MASK) != 0;
    }

    /**
     * @dev Sets the redeem duration of the NFT
     * @param self The NFT configuration
     * @param redeemDuration The redeem duration
     **/
    function setRedeemDuration(
        DataTypes.NftConfigurationMap memory self,
        uint256 redeemDuration
    ) internal pure {
        require(
            redeemDuration <= MAX_VALID_REDEEM_DURATION,
            Errors.RC_INVALID_REDEEM_DURATION
        );

        self.data =
            (self.data & REDEEM_DURATION_MASK) |
            (redeemDuration << REDEEM_DURATION_START_BIT_POSITION);
    }

    /**
     * @dev Gets the redeem duration of the NFT
     * @param self The NFT configuration
     * @return The redeem duration
     **/
    function getRedeemDuration(
        DataTypes.NftConfigurationMap storage self
    ) internal view returns (uint256) {
        return
            (self.data & ~REDEEM_DURATION_MASK) >>
            REDEEM_DURATION_START_BIT_POSITION;
    }

    /**
     * @dev Sets the auction duration of the NFT
     * @param self The NFT configuration
     * @param auctionDuration The auction duration
     **/
    function setAuctionDuration(
        DataTypes.NftConfigurationMap memory self,
        uint256 auctionDuration
    ) internal pure {
        require(
            auctionDuration <= MAX_VALID_AUCTION_DURATION,
            Errors.RC_INVALID_AUCTION_DURATION
        );

        self.data =
            (self.data & AUCTION_DURATION_MASK) |
            (auctionDuration << AUCTION_DURATION_START_BIT_POSITION);
    }

    /**
     * @dev Gets the auction duration of the NFT
     * @param self The NFT configuration
     * @return The auction duration
     **/
    function getAuctionDuration(
        DataTypes.NftConfigurationMap storage self
    ) internal view returns (uint256) {
        return
            (self.data & ~AUCTION_DURATION_MASK) >>
            AUCTION_DURATION_START_BIT_POSITION;
    }

    /**
     * @dev Sets the redeem fine of the NFT
     * @param self The NFT configuration
     * @param redeemFine The redeem duration
     **/
    function setRedeemFine(
        DataTypes.NftConfigurationMap memory self,
        uint256 redeemFine
    ) internal pure {
        require(
            redeemFine <= MAX_VALID_REDEEM_FINE,
            Errors.RC_INVALID_REDEEM_FINE
        );

        self.data =
            (self.data & REDEEM_FINE_MASK) |
            (redeemFine << REDEEM_FINE_START_BIT_POSITION);
    }

    /**
     * @dev Gets the redeem fine of the NFT
     * @param self The NFT configuration
     * @return The redeem fine
     **/
    function getRedeemFine(
        DataTypes.NftConfigurationMap storage self
    ) internal view returns (uint256) {
        return
            (self.data & ~REDEEM_FINE_MASK) >> REDEEM_FINE_START_BIT_POSITION;
    }

    /**
     * @dev Sets the redeem threshold of the NFT
     * @param self The NFT configuration
     * @param redeemThreshold The redeem duration
     **/
    function setRedeemThreshold(
        DataTypes.NftConfigurationMap memory self,
        uint256 redeemThreshold
    ) internal pure {
        require(
            redeemThreshold <= MAX_VALID_REDEEM_THRESHOLD,
            Errors.RC_INVALID_REDEEM_THRESHOLD
        );

        self.data =
            (self.data & REDEEM_THRESHOLD_MASK) |
            (redeemThreshold << REDEEM_THRESHOLD_START_BIT_POSITION);
    }

    /**
     * @dev Gets the redeem threshold of the NFT
     * @param self The NFT configuration
     * @return The redeem threshold
     **/
    function getRedeemThreshold(
        DataTypes.NftConfigurationMap storage self
    ) internal view returns (uint256) {
        return
            (self.data & ~REDEEM_THRESHOLD_MASK) >>
            REDEEM_THRESHOLD_START_BIT_POSITION;
    }

    /**
     * @dev Sets the min & max threshold of the NFT
     * @param self The NFT configuration
     * @param minBidFine The min bid fine
     **/
    function setMinBidFine(
        DataTypes.NftConfigurationMap memory self,
        uint256 minBidFine
    ) internal pure {
        require(
            minBidFine <= MAX_VALID_MIN_BIDFINE,
            Errors.RC_INVALID_MIN_BID_FINE
        );

        self.data =
            (self.data & MIN_BIDFINE_MASK) |
            (minBidFine << MIN_BIDFINE_START_BIT_POSITION);
    }

    /**
     * @dev Gets the min bid fine of the NFT
     * @param self The NFT configuration
     * @return The min bid fine
     **/
    function getMinBidFine(
        DataTypes.NftConfigurationMap storage self
    ) internal view returns (uint256) {
        return ((self.data & ~MIN_BIDFINE_MASK) >>
            MIN_BIDFINE_START_BIT_POSITION);
    }

    /**
     * @dev Gets the configuration flags of the NFT
     * @param self The NFT configuration
     * @return The state flags representing active, frozen
     **/
    function getFlags(
        DataTypes.NftConfigurationMap storage self
    ) internal view returns (bool, bool) {
        uint256 dataLocal = self.data;

        return (
            (dataLocal & ~ACTIVE_MASK) != 0,
            (dataLocal & ~FROZEN_MASK) != 0
        );
    }

    /**
     * @dev Gets the configuration flags of the NFT from a memory object
     * @param self The NFT configuration
     * @return The state flags representing active, frozen
     **/
    function getFlagsMemory(
        DataTypes.NftConfigurationMap memory self
    ) internal pure returns (bool, bool) {
        return (
            (self.data & ~ACTIVE_MASK) != 0,
            (self.data & ~FROZEN_MASK) != 0
        );
    }

    /**
     * @dev Gets the collateral configuration paramters of the NFT
     * @param self The NFT configuration
     * @return The state params representing ltv, liquidation threshold, liquidation bonus
     **/
    function getCollateralParams(
        DataTypes.NftConfigurationMap storage self
    ) internal view returns (uint256, uint256, uint256) {
        uint256 dataLocal = self.data;

        return (
            dataLocal & ~LTV_MASK,
            (dataLocal & ~LIQUIDATION_THRESHOLD_MASK) >>
                LIQUIDATION_THRESHOLD_START_BIT_POSITION,
            (dataLocal & ~LIQUIDATION_BONUS_MASK) >>
                LIQUIDATION_BONUS_START_BIT_POSITION
        );
    }

    /**
     * @dev Gets the auction configuration paramters of the NFT
     * @param self The NFT configuration
     * @return The state params representing redeem duration, auction duration, redeem fine
     **/
    function getAuctionParams(
        DataTypes.NftConfigurationMap storage self
    ) internal view returns (uint256, uint256, uint256, uint256) {
        uint256 dataLocal = self.data;

        return (
            (dataLocal & ~REDEEM_DURATION_MASK) >>
                REDEEM_DURATION_START_BIT_POSITION,
            (dataLocal & ~AUCTION_DURATION_MASK) >>
                AUCTION_DURATION_START_BIT_POSITION,
            (dataLocal & ~REDEEM_FINE_MASK) >> REDEEM_FINE_START_BIT_POSITION,
            (dataLocal & ~REDEEM_THRESHOLD_MASK) >>
                REDEEM_THRESHOLD_START_BIT_POSITION
        );
    }

    /**
     * @dev Gets the collateral configuration paramters of the NFT from a memory object
     * @param self The NFT configuration
     * @return The state params representing ltv, liquidation threshold, liquidation bonus
     **/
    function getCollateralParamsMemory(
        DataTypes.NftConfigurationMap memory self
    ) internal pure returns (uint256, uint256, uint256) {
        return (
            self.data & ~LTV_MASK,
            (self.data & ~LIQUIDATION_THRESHOLD_MASK) >>
                LIQUIDATION_THRESHOLD_START_BIT_POSITION,
            (self.data & ~LIQUIDATION_BONUS_MASK) >>
                LIQUIDATION_BONUS_START_BIT_POSITION
        );
    }

    /**
     * @dev Gets the auction configuration paramters of the NFT from a memory object
     * @param self The NFT configuration
     * @return The state params representing redeem duration, auction duration, redeem fine
     **/
    function getAuctionParamsMemory(
        DataTypes.NftConfigurationMap memory self
    ) internal pure returns (uint256, uint256, uint256, uint256) {
        return (
            (self.data & ~REDEEM_DURATION_MASK) >>
                REDEEM_DURATION_START_BIT_POSITION,
            (self.data & ~AUCTION_DURATION_MASK) >>
                AUCTION_DURATION_START_BIT_POSITION,
            (self.data & ~REDEEM_FINE_MASK) >> REDEEM_FINE_START_BIT_POSITION,
            (self.data & ~REDEEM_THRESHOLD_MASK) >>
                REDEEM_THRESHOLD_START_BIT_POSITION
        );
    }

    /**
     * @dev Gets the min & max bid fine of the NFT
     * @param self The NFT configuration
     * @return The min & max bid fine
     **/
    function getMinBidFineMemory(
        DataTypes.NftConfigurationMap memory self
    ) internal pure returns (uint256) {
        return ((self.data & ~MIN_BIDFINE_MASK) >>
            MIN_BIDFINE_START_BIT_POSITION);
    }
}
