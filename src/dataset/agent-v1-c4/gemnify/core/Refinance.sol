// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import {IVault} from "./interfaces/IVault.sol";
import {IRewardTracker} from "../staking/interfaces/IRewardTracker.sol";
import {IRefinance} from "./interfaces/IRefinance.sol";
import {IUlpManager} from "./interfaces/IUlpManager.sol";
import {ICrossChain} from "./interfaces/ICrossChain.sol";
import {ICertiNft} from "./interfaces/ICertiNft.sol";

import {DataTypes} from "./libraries/types/DataTypes.sol";
import {Constants} from "./libraries/helpers/Constants.sol";

contract Refinance is
    IRefinance,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    struct UserHFInfo {
        address user;
        uint256 hf;
    }

    struct FloorPrice {
        address token;
        uint256 floorPrice;
    }

    uint256 internal beforeRefinanceETHShare;
    uint256 internal afterRefinanceETHShare;
    address payable public refinanceKeeper;
    address public weth;

    IVault public override vault;
    address public override feeUlpTracker;
    address public ulp;
    address public ulpManager;

    ICrossChain public crossChainContract;

    address[] public refinanceUsers;
    address[] public refinanceNfts;
    uint256[] public refinanceTokenIds;
    address[] public notRefinanceUsers;
    address[] public refinanceNotFoundUsers;

    modifier onlyRefinanceKeeper() {
        require(msg.sender == refinanceKeeper, "refinance: forbidden");
        _;
    }

    function initialize(
        address _weth,
        address _vault,
        address _feeUlpTracker,
        address _ulp,
        address _ulpManager
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        weth = _weth;
        vault = IVault(_vault);
        feeUlpTracker = _feeUlpTracker;
        ulp = _ulp;
        ulpManager = _ulpManager;
    }

    function setRefinanceKeeper(
        address payable _refinanceKeeper
    ) external onlyOwner {
        refinanceKeeper = _refinanceKeeper;
    }

    function setCrossChainContract(
        address _crossChainContract
    ) external onlyOwner {
        require(
            _crossChainContract != address(0),
            "refinance: crossChainContract can't be null"
        );
        crossChainContract = ICrossChain(_crossChainContract);
    }

    function setBeforeRefinanceETHShare(uint256 _ethShare) external onlyOwner {
        beforeRefinanceETHShare = _ethShare;
    }

    function getBeforeRefinanceETHShare()
        external
        view
        override
        returns (uint256)
    {
        return beforeRefinanceETHShare;
    }

    function setAfterRefinanceETHShare(uint256 _ethShare) external onlyOwner {
        afterRefinanceETHShare = _ethShare;
    }

    function getAfterRefinanceETHShare()
        external
        view
        override
        returns (uint256)
    {
        return afterRefinanceETHShare;
    }

    function refinance()
        external
        payable
        nonReentrant
        onlyRefinanceKeeper
        returns (bool)
    {
        // calculate eth share
        uint256 aum = IUlpManager(ulpManager).getAum(true);
        uint256 ethShare = calculateETHShare(aum, 0);

        if (ethShare > beforeRefinanceETHShare) {
            return true;
        }

        // calculate account hf
        UserHFInfo[] memory userHFInfos = calculateUsersHF();
        // sort nft floor price
        FloorPrice[] memory floorPrices = sortFloorPrice();

        resetRefinanceArray();
        uint256 ethAmountAddition = 0;
        uint256 ethShareUpdated;

        while (true) {
            (
                UserHFInfo memory smallestHFUserInfo,
                uint256 index
            ) = smallestHFUser(userHFInfos);
            if (smallestHFUserInfo.hf == 0) {
                break;
            }

            bool refinanceTokenFound;
            for (uint256 i = 0; i < floorPrices.length; i++) {
                address token = floorPrices[i].token;
                DataTypes.NftStatus[] memory tokenIds = vault.getUserTokenIds(
                    smallestHFUserInfo.user,
                    token
                );

                if (tokenIds.length > 0) {
                    for (uint256 t = 0; t < tokenIds.length; t++) {
                        (address certiNft, uint256 ltv) = vault.getNftInfo(
                            token
                        );

                        if (
                            !tokenIds[t].isRefinanced &&
                            ICertiNft(certiNft).tokenLtv(tokenIds[t].tokenId) <=
                            ltv
                        ) {
                            refinanceTokenFound = true;

                            // update refinance status
                            vault.updateNftRefinanceStatus(
                                smallestHFUserInfo.user,
                                token,
                                tokenIds[t].tokenId
                            );

                            uint256 borrowAmount = (vault.getBendDAOAssetPrice(
                                token
                            ) * ltv) / Constants.PERCENTAGE_FACTOR;
                            ethAmountAddition += borrowAmount;
                            refinanceUsers.push(smallestHFUserInfo.user);
                            refinanceNfts.push(token);
                            refinanceTokenIds.push(tokenIds[t].tokenId);
                            break;
                        }
                    }
                    if (refinanceTokenFound) {
                        break;
                    }
                }
            }

            if (!refinanceTokenFound) {
                refinanceNotFoundUsers.push(smallestHFUserInfo.user);
            } else {
                ethShareUpdated = calculateETHShare(aum, ethAmountAddition);
                if (ethShareUpdated > afterRefinanceETHShare) {
                    break;
                }
                // calculate account hf
                userHFInfos[index] = calculateUserHF(smallestHFUserInfo.user);
            }
        }

        // burn certificate nft and nft token
        if (ethShareUpdated > afterRefinanceETHShare) {
            for (uint256 i = 0; i < refinanceUsers.length; i++) {
                (address certiNft, ) = vault.getNftInfo(refinanceNfts[i]);
                vault.burnCNft(certiNft, refinanceTokenIds[i]);
                vault.burnNToken(
                    refinanceNfts[i],
                    (ICertiNft(certiNft).tokenLtv(refinanceTokenIds[i]) *
                        vault.getTokenDecimal(refinanceNfts[i])) /
                        Constants.PERCENTAGE_FACTOR
                );
            }

            uint256 crossChainFee = crossChainContract.estimateRefinanceFee(
                refinanceUsers,
                refinanceNfts,
                refinanceTokenIds
            );
            require(
                msg.value >= crossChainFee,
                "refinance: crossChain fee not enough"
            );
            crossChainContract.sendRefinanceNftMsg{value: msg.value}(
                refinanceUsers,
                refinanceNfts,
                refinanceTokenIds,
                refinanceKeeper
            );
        }
        return true;
    }

    function calculateETHShare(
        uint256 aum,
        uint256 ethAmountAddition
    ) public view returns (uint256) {
        (uint256 ethAmount, , , , , , ) = vault.getPoolInfo(weth);
        if (ethAmountAddition > 0) {
            ethAmount = ethAmount + ethAmountAddition;
        }

        uint256 ethPrice = vault.getMaxPrice(weth);
        DataTypes.TokenInfo memory ethTokenInfo = vault.getTokenInfo(weth);
        uint256 ethValue = (ethAmount * ethPrice) / 10 ** ethTokenInfo.tokenDecimal;

        return (ethValue * Constants.PERCENTAGE_FACTOR) / aum;
    }

    function calculateUserHF(
        address user
    ) internal view returns (UserHFInfo memory) {
        NFTTokenData[] memory nftTokenDatas = getAllNFTTokensData();

        uint256 ulpPrice = IUlpManager(ulpManager).getPrice(false);
        uint256 ulpAmount = IRewardTracker(feeUlpTracker).depositBalances(
            user,
            ulp
        );
        uint256 userHF = 0;

        if (ulpAmount > 0) {
            uint256 userUlpValue = ulpPrice * ulpAmount;
            uint256 userNftValue;

            for (uint256 i = 0; i < nftTokenDatas.length; i++) {
                NFTTokenData memory nftTokenData = nftTokenDatas[i];
                DataTypes.NftStatus[] memory tokenIds = vault.getUserTokenIds(
                    user,
                    nftTokenData.token
                );

                for (uint256 m = 0; m < tokenIds.length; m++) {
                    if (!tokenIds[m].isRefinanced) {
                        userNftValue += (nftTokenData.price * nftTokenData.ltv);
                    }
                }
            }

            if (userNftValue > 0) {
                userHF =
                    (userUlpValue * Constants.PERCENTAGE_FACTOR) /
                    userNftValue;
            }
        }
        return UserHFInfo({user: user, hf: userHF});
    }

    function calculateUsersHF() public view returns (UserHFInfo[] memory) {
        uint256 usersLength = vault.nftUsersLength(); // user's nft count
        UserHFInfo[] memory userHFInfos = new UserHFInfo[](usersLength);

        for (uint256 i = 0; i < usersLength; i++) {
            UserHFInfo memory userHFInfo = calculateUserHF(vault.nftUsers(i));
            if (userHFInfo.hf > 0) {
                userHFInfos[i] = userHFInfo;
            }
        }
        return userHFInfos;
    }

    function smallestHFUser(
        UserHFInfo[] memory originUserHFInfo
    ) internal view returns (UserHFInfo memory, uint256) {
        UserHFInfo memory smallestHFUserInfo;
        uint256 smallestHF = type(uint256).max;
        uint256 index;

        for (uint256 i = 0; i < originUserHFInfo.length; i++) {
            bool refinanceNotFound = false;
            for (uint256 j = 0; j < refinanceNotFoundUsers.length; j++) {
                if (originUserHFInfo[i].user == refinanceNotFoundUsers[j]) {
                    refinanceNotFound = true;
                    break;
                }
            }

            if (
                !refinanceNotFound &&
                originUserHFInfo[i].hf > 0 &&
                originUserHFInfo[i].hf < smallestHF
            ) {
                smallestHFUserInfo = originUserHFInfo[i];
                smallestHF = originUserHFInfo[i].hf;
                index = i;
            }
        }

        return (smallestHFUserInfo, index);
    }

    function sortFloorPrice() internal view returns (FloorPrice[] memory) {
        (uint256 allTokenLength, address[] memory allWhitelistedTokens) = vault
            .getWhitelistedToken();

        uint256 nftTokenLength = 0;
        for (uint256 i = 0; i < allTokenLength; i++) {
            address token = allWhitelistedTokens[i];
            DataTypes.TokenInfo memory tokenInfo = vault.getTokenInfo(token);
            if (!tokenInfo.isWhitelistedToken || tokenInfo.isStableToken) {
                continue;
            }
            nftTokenLength++;
        }

        FloorPrice[] memory floorPrices = new FloorPrice[](nftTokenLength);
        uint256 nftTokenIndex;
        for (uint256 i = 0; i < allTokenLength; i++) {
            address token = allWhitelistedTokens[i];
            DataTypes.TokenInfo memory tokenInfo = vault.getTokenInfo(token);
            if (!tokenInfo.isWhitelistedToken || tokenInfo.isStableToken) {
                continue;
            }

            uint256 price = vault.getMaxPrice(token);
            floorPrices[nftTokenIndex] = FloorPrice({
                token: token,
                floorPrice: price
            });
            nftTokenIndex++;
        }

        // sort floorPrice
        for (uint256 i = 0; i < nftTokenLength - 1; i++) {
            for (uint256 j = 0; j < nftTokenLength - i - 1; j++) {
                if (floorPrices[j].floorPrice > floorPrices[j + 1].floorPrice) {
                    FloorPrice memory temp = floorPrices[j];
                    floorPrices[j] = floorPrices[j + 1];
                    floorPrices[j + 1] = temp;
                }
            }
        }
        return floorPrices;
    }

    struct NFTTokenData {
        address token;
        uint256 price;
        uint256 ltv;
    }

    function getAllNFTTokensData()
        internal
        view
        returns (NFTTokenData[] memory)
    {
        (uint256 length, address[] memory allWhitelistedTokens) = vault
            .getWhitelistedToken();
        NFTTokenData[] memory nftTokenDatas = new NFTTokenData[](length);
        for (uint256 i = 0; i < length; i++) {
            address token = allWhitelistedTokens[i];
            DataTypes.TokenInfo memory tokenInfo = vault.getTokenInfo(token);

            if (!tokenInfo.isWhitelistedToken || tokenInfo.isStableToken) {
                continue;
            }

            uint256 price = vault.getMaxPrice(token);
            (, uint256 ltv) = vault.getNftInfo(token);

            nftTokenDatas[i] = NFTTokenData({
                token: token,
                price: price,
                ltv: ltv
            });
        }
        return nftTokenDatas;
    }

    function getHFRanking(
        address user
    ) public view returns (uint256, uint256, uint256) {
        UserHFInfo[] memory userHFInfos = calculateUsersHF();
        uint256 userHFRanking = 0;
        uint256 userHF = 0;
        bool userFound;
        for (uint256 i = 0; i < userHFInfos.length; i++) {
            if (userHFInfos[i].user == user) {
                userHF = userHFInfos[i].hf;
                userFound = true;
                break;
            }
        }

        if (!userFound) {
            return (0, 0, userHFInfos.length);
        }

        for (uint256 i = 0; i < userHFInfos.length; i++) {
            if (userHFInfos[i].hf < userHF) {
                userHFRanking++;
            }
        }
        return (userHF, userHFRanking + 1, userHFInfos.length);
    }

    function resetRefinanceArray() private {
        if (refinanceUsers.length > 0) {
            delete refinanceUsers;
            delete refinanceNfts;
            delete refinanceTokenIds;
        }
        if (refinanceNotFoundUsers.length > 0) {
            delete refinanceNotFoundUsers;
        }
    }
}
