// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {DataTypes} from "../libraries/types/DataTypes.sol";

interface IVault {
    function buyETHG(
        address _token,
        address _receiver
    ) external returns (uint256);

    function sellETHG(
        address _token,
        address _receiver
    ) external returns (uint256);

    function swap(
        address _tokenIn,
        address _tokenOut,
        address _receiver
    ) external returns (uint256);

    function increasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong
    ) external;

    function decreasePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver
    ) external returns (uint256);

    function liquidatePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        address _feeReceiver
    ) external;

    function getMaxPrice(address _token) external view returns (uint256);

    function getMinPrice(address _token) external view returns (uint256);

    function getDelta(
        address _indexToken,
        uint256 _size,
        uint256 _averagePrice,
        bool _isLong,
        uint256 _lastIncreasedTime
    ) external view returns (bool, uint256);

    function getPosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) external view returns (DataTypes.Position memory);

    function getRedemptionAmount(
        address _token,
        uint256 _ethgAmount
    ) external view returns (uint256);

    function tokenToUsdMin(
        address _token,
        uint256 _tokenAmount
    ) external view returns (uint256);

    function mintCNft(
        address _cNft,
        address _to,
        uint256 _tokenId,
        uint256 _ltv
    ) external;

    function mintNToken(address _nToken, uint256 _amount) external;

    function burnCNft(address _cNft, uint256 _tokenId) external;

    function burnNToken(address _nToken, uint256 _amount) external;

    function getBendDAOAssetPrice(address _nft) external view returns (uint256);

    function addNftToUser(
        address _user,
        address _nft,
        uint256 _tokenId
    ) external;

    function removeNftFromUser(
        address _user,
        address _nft,
        uint256 _tokenId
    ) external;

    function isNftDepsoitedForUser(
        address _user,
        address _nft,
        uint256 _tokenId
    ) external view returns (bool);

    function getETHGAmountWhenRedeemNft(
        address _nft,
        uint256 _tokenId,
        uint256 _ethAmount
    ) external view returns (uint256, uint256);

    function getTokenDecimal(address _token) external view returns (uint256);

    function getBorrowingRate()
        external
        view
        returns (uint256, uint256, uint256);

    function getFundingFactor(
        address _token
    ) external view returns (uint256, uint256);

    function getPoolInfo(
        address _token
    )
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256);

    function getWhitelistedToken()
        external
        view
        returns (uint256, address[] memory);

    function getTokenInfo(
        address _token
    ) external view returns (DataTypes.TokenInfo memory);

    function nftUsers(uint256) external view returns (address);

    function nftUsersLength() external view returns (uint256);

    function getNftInfo(
        address _token
    ) external view returns (address, uint256);

    function getUserTokenIds(
        address _user,
        address _nft
    ) external view returns (DataTypes.NftStatus[] memory);

    function updateNftRefinanceStatus(
        address _user,
        address _nft,
        uint256 _tokenId
    ) external;

    function directPoolDeposit(address _token) external;

    function getFeeBasisPoints(
        address _token,
        uint256 _ethgDelta,
        uint256 _feeBasisPoints,
        uint256 _taxBasisPoints,
        bool _increment
    ) external view returns (uint256);

    function getFees() external view returns (DataTypes.SetFeesParams memory);
}
