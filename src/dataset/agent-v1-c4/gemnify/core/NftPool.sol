// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {IERC20Upgradeable, SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {EnumerableSetUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import {INftPool} from "./interfaces/INftPool.sol";
import {ILendPool} from "./BendDAO/interfaces/ILendPool.sol";
import {IDebtToken} from "./BendDAO/interfaces/IDebtToken.sol";
import {IWETHGateway} from "./BendDAO/interfaces/IWETHGateway.sol";
import {INFTOracleGetter} from "./BendDAO/interfaces/INFTOracleGetter.sol";
import {NftConfiguration} from "./BendDAO/libraries/configuration/NftConfiguration.sol";
import {DataTypes} from "./BendDAO/libraries/types/DataTypes.sol";
import {ICrossChain} from "./interfaces/ICrossChain.sol";
import {IWETH} from "../tokens/interfaces/IWETH.sol";
import {Constants} from "./libraries/helpers/Constants.sol";

contract NftPool is
    INftPool,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using NftConfiguration for DataTypes.NftConfigurationMap;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    EnumerableSetUpgradeable.AddressSet private _whitelistedNfts;

    address public weth;
    address public vault;
    address payable public keeper; // cross eth to L2 vault contract;
    ICrossChain public crossChainContract;

    ILendPool public lendPool; // BendDAO lend pool address, for refinance;
    IWETHGateway public bendWETHGateway; // BendDAO WETH Gateway
    INFTOracleGetter public bendOracle; // BendDAO oracle

    struct TokenRefinanceInfo {
        uint256 tokenId;
        bool hasRefinanced;
    }

    mapping(address => mapping(address => TokenRefinanceInfo[]))
        public nftsForUser; // user->nft->tokenIds
    uint256 public repayBufferAmount; // denominator is 10000
    IDebtToken public bendDebtToken;

    receive() external payable {
        require(
            msg.sender == address(bendWETHGateway),
            "nftPool: invalid sender"
        );
    }

    modifier onlyCrossChain() {
        require(
            msg.sender == address(crossChainContract),
            "nftPool: forbidden"
        );
        _;
    }

    modifier onlyKeeper() {
        require(msg.sender == keeper, "nftPool: forbidden");
        _;
    }

    modifier onlySupportNft(address[] calldata _nfts) {
        for (uint256 i = 0; i < _nfts.length; i++) {
            bool supportNft;
            for (uint256 j = 0; j < _whitelistedNfts.length(); j++) {
                if (_whitelistedNfts.at(j) == _nfts[i]) {
                    supportNft = true;
                    break;
                }
            }
            require(supportNft, "nftPool: not support nft");
        }
        _;
    }

    function initialize(
        address _lendPool,
        address _bendOracle,
        address _bendWethGateway,
        address _bendDebtToken,
        address _weth,
        address _vault
    ) external initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        lendPool = ILendPool(_lendPool);
        bendWETHGateway = IWETHGateway(_bendWethGateway);
        bendOracle = INFTOracleGetter(_bendOracle);
        bendDebtToken = IDebtToken(_bendDebtToken);
        weth = _weth;
        vault = _vault;
    }

    function setCrossChainContract(
        address _crossChainContract
    ) external onlyOwner {
        require(
            _crossChainContract != address(0),
            "nftPool: crossChainContract can't be zero"
        );
        crossChainContract = ICrossChain(_crossChainContract);
    }

    function setVault(address _addr) external onlyOwner {
        require(_addr != address(0), "nftPool: vault can't be zero");
        vault = _addr;
    }

    function addWhitelistedNfts(address _nft) external onlyOwner {
        require(_nft != address(0), "nftPool: nft can't be null");
        _whitelistedNfts.add(_nft);
    }

    function removeWhitelistedNft(address _nft) external onlyOwner {
        require(_nft != address(0), "nftPool: nft can't be null");
        _whitelistedNfts.remove(_nft);
    }

    function setKeeper(address payable _keeper) external onlyOwner {
        require(_keeper != address(0), "nftPool: keeper can't be null");
        keeper = _keeper;
    }

    function setRepayBufferAmount(
        uint256 _repayBufferAmount
    ) external onlyOwner {
        require(
            _repayBufferAmount < Constants.PERCENTAGE_FACTOR,
            "nftPool: invalid buffer amount"
        );
        repayBufferAmount = _repayBufferAmount;
    }

    function deposit(
        address[] calldata _nfts,
        uint256[][] calldata _tokenIds
    ) public payable override onlySupportNft(_nfts) nonReentrant whenNotPaused {
        address user = msg.sender;
        uint256 crossChainFee = crossChainContract.estimateDepositFee(
            user,
            _nfts,
            _tokenIds
        );
        require(
            msg.value >= crossChainFee,
            "NftPool: crossChain fee not enough"
        );

        _checkDepositValid(user, _nfts, _tokenIds);
        _deposit(user, _nfts, _tokenIds, true);

        crossChainContract.sendDepositNftMsg{value: msg.value}(
            payable(user),
            _nfts,
            _tokenIds
        );
    }

    function _deposit(
        address _user,
        address[] memory _nfts,
        uint256[][] memory _tokenIds,
        bool _tokenFromUser
    ) internal {
        _checkDuplicateNfts(_nfts);
        _checkDuplicateTokenIds(_tokenIds);

        address _nft;
        uint256 _tokenId;
        for (uint256 i = 0; i < _nfts.length; i++) {
            if (_tokenFromUser) {
                _nft = _nfts[i];
                TokenRefinanceInfo[] storage tokenRefinanceInfos = nftsForUser[
                    _user
                ][_nft];
                require(_tokenIds[i].length > 0, "nftPool: empty tokenIds");
                for (uint256 j = 0; j < _tokenIds[i].length; j++) {
                    _tokenId = _tokenIds[i][j];
                    IERC721Upgradeable(_nft).safeTransferFrom(
                        _user,
                        address(this),
                        _tokenId
                    );
                    tokenRefinanceInfos.push(
                        TokenRefinanceInfo({
                            tokenId: _tokenId,
                            hasRefinanced: false
                        })
                    );
                }
            }
            emit NftDeposited(_nft, _tokenIds[i], _user);
        }
    }

    function withdraw(
        address _user,
        address[] calldata _nfts,
        uint256[][] calldata _tokenIds
    )
        external
        override
        onlyCrossChain
        onlySupportNft(_nfts)
        nonReentrant
        whenNotPaused
    {
        _checkDuplicateNfts(_nfts);
        _checkDuplicateTokenIds(_tokenIds);
        _checkWithdrawValid(_user, _nfts, _tokenIds);

        uint256 _tokenId;
        address _nft;

        for (uint256 i = 0; i < _nfts.length; i++) {
            require(_tokenIds[i].length > 0, "nftPool: empty tokenIds");
            _nft = _nfts[i];
            for (uint256 j = 0; j < _tokenIds[i].length; j++) {
                _tokenId = _tokenIds[i][j];
                IERC721Upgradeable(_nft).safeTransferFrom(
                    address(this),
                    _user,
                    _tokenId
                );

                TokenRefinanceInfo[] storage tokenRefinanceInfos = nftsForUser[
                    _user
                ][_nft];
                for (uint256 m = 0; m < tokenRefinanceInfos.length; m++) {
                    if (tokenRefinanceInfos[m].tokenId == _tokenId) {
                        require(
                            tokenRefinanceInfos[m].hasRefinanced == false,
                            "nftPool: token has refinanced"
                        );
                        tokenRefinanceInfos[m] = tokenRefinanceInfos[
                            tokenRefinanceInfos.length - 1
                        ];
                        tokenRefinanceInfos.pop();
                        break;
                    }
                }
            }

            emit NftWithdrawn(_nft, _tokenIds[i], _user);
        }
    }

    function emergencyWithdraw(
        address _receiver,
        address _nft,
        uint256 _tokenId
    ) external onlyOwner {
        (bool tokenInPool, bool tokenRefinanced) = getTokenStatus(
            _receiver,
            _nft,
            _tokenId
        );
        require(tokenInPool && !tokenRefinanced, "nftPool: token not valid");

        TokenRefinanceInfo[] storage tokenRefinanceInfos = nftsForUser[
            _receiver
        ][_nft];
        for (uint256 i = 0; i < tokenRefinanceInfos.length; i++) {
            if (tokenRefinanceInfos[i].tokenId == _tokenId) {
                tokenRefinanceInfos[i] = tokenRefinanceInfos[
                    tokenRefinanceInfos.length - 1
                ];
                tokenRefinanceInfos.pop();
                break;
            }
        }

        IERC721Upgradeable(_nft).safeTransferFrom(
            address(this),
            _receiver,
            _tokenId
        );
    }

    function refinance(
        address[] calldata _users,
        address[] calldata _nfts,
        uint256[] calldata _tokenIds
    )
        external
        override
        onlyCrossChain
        onlySupportNft(_nfts)
        nonReentrant
        whenNotPaused
    {
        require(
            _nfts.length == _users.length,
            "nftPool: users length not equal"
        );
        require(
            _nfts.length == _tokenIds.length,
            "nftPool: tokenIds length not equal"
        );
        for (uint i = 0; i < _nfts.length; i++) {
            (bool tokenInPool, bool tokenRefinanced) = getTokenStatus(
                _users[i],
                _nfts[i],
                _tokenIds[i]
            );
            require(tokenInPool, "nftPool: token not in pool");
            require(!tokenRefinanced, "nftPool: token has refinanced");
        }

        for (uint i = 0; i < _nfts.length; i++) {
            address _user = _users[i];
            address _nft = _nfts[i];
            uint256 _tokenId = _tokenIds[i];
            TokenRefinanceInfo[] storage tokenRefinanceInfos = nftsForUser[
                _user
            ][_nft];
            DataTypes.NftConfigurationMap memory nftConfigurationMap = lendPool
                .getNftConfiguration(_nft);
            uint256 ltv = nftConfigurationMap.data & ~NftConfiguration.LTV_MASK;
            uint256 floorPrice = bendOracle.getAssetPrice(_nft);
            uint256 amount = (floorPrice * ltv) / Constants.PERCENTAGE_FACTOR;

            IERC721Upgradeable(_nft).approve(
                address(bendWETHGateway),
                _tokenId
            );
            bendWETHGateway.borrowETH(
                amount,
                _nft,
                _tokenId,
                address(this),
                0x00
            );

            for (uint256 j = 0; j < tokenRefinanceInfos.length; j++) {
                if (tokenRefinanceInfos[j].tokenId == _tokenId) {
                    tokenRefinanceInfos[j].hasRefinanced = true;
                    break;
                }
            }

            emit NftRefinance(_nft, _tokenId, _user, amount, weth);
        }
    }

    function DebtTokenApproveDelegation() external onlyOwner {
        bendDebtToken.approveDelegation(
            address(bendWETHGateway),
            type(uint256).max
        );
    }

    function swapRefinancedETH()
        external
        payable
        override
        onlyKeeper
        nonReentrant
        whenNotPaused
    {
        uint256 crossChainFee = crossChainContract.estimateSwapFee(vault);
        require(
            msg.value >= crossChainFee,
            "nftPool: crossChain fee is not enough"
        );

        uint256 ethBalance = address(this).balance;
        crossChainContract.swapETH{value: ethBalance}(
            payable(msg.sender),
            vault,
            ethBalance - msg.value
        );
    }

    function onERC721Received(
        address /*operator*/,
        address /*from*/,
        uint256 /*tokenId*/,
        bytes calldata /*data*/
    ) external view returns (bytes4) {
        bool supportNft;
        for (uint256 i = 0; i < _whitelistedNfts.length(); i++) {
            if (_whitelistedNfts.at(i) == msg.sender) {
                supportNft = true;
            }
        }
        require(supportNft, "nftPool: not support nft");
        return this.onERC721Received.selector;
    }

    function _checkDuplicateNfts(address[] memory _nfts) internal pure {
        for (uint256 i = 0; i < _nfts.length; i++) {
            for (uint256 j = i + 1; j < _nfts.length; j++) {
                require(_nfts[i] != _nfts[j], "nftPool: duplicate nfts");
            }
        }
    }

    function _checkDuplicateTokenIds(
        uint256[][] memory _tokenIds
    ) internal pure {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            for (uint256 j = 0; j < _tokenIds[i].length; j++) {
                for (uint256 k = j + 1; k < _tokenIds[i].length; k++) {
                    require(
                        _tokenIds[i][j] != _tokenIds[i][k],
                        "nftPool: duplicate tokenIds"
                    );
                }
            }
        }
    }

    function _checkWithdrawValid(
        address _user,
        address[] calldata _nfts,
        uint256[][] calldata _tokenIds
    ) internal view {
        uint256 _tokenId;
        address _nft;
        for (uint256 i = 0; i < _nfts.length; i++) {
            _nft = _nfts[i];
            require(_tokenIds[i].length > 0, "nftPool: empty tokenIds");
            for (uint256 j = 0; j < _tokenIds[i].length; j++) {
                _tokenId = _tokenIds[i][j];
                TokenRefinanceInfo[] storage tokenRefinanceInfos = nftsForUser[
                    _user
                ][_nft];
                bool tokenIdValid;
                for (uint256 m = 0; m < tokenRefinanceInfos.length; m++) {
                    if (
                        tokenRefinanceInfos[m].tokenId == _tokenId &&
                        !tokenRefinanceInfos[m].hasRefinanced
                    ) {
                        tokenIdValid = true;
                        break;
                    }
                }
                require(tokenIdValid, "nftPool: tokenId not valid");
            }
        }
    }

    function _checkDepositValid(
        address _user,
        address[] memory _nfts,
        uint256[][] memory _tokenIds
    ) internal view {
        uint256 _tokenId;
        address _nft;
        for (uint256 i = 0; i < _nfts.length; i++) {
            _nft = _nfts[i];
            require(_tokenIds[i].length > 0, "nftPool: empty tokenIds");
            for (uint256 j = 0; j < _tokenIds[i].length; j++) {
                _tokenId = _tokenIds[i][j];
                TokenRefinanceInfo[] storage tokenRefinanceInfos = nftsForUser[
                    _user
                ][_nft];
                bool tokenDeposited;
                for (uint256 m = 0; m < tokenRefinanceInfos.length; m++) {
                    if (tokenRefinanceInfos[m].tokenId == _tokenId) {
                        tokenDeposited = true;
                        break;
                    }
                }
                require(!tokenDeposited, "nftPool: token already in pool");
            }
        }
    }

    function repayETH(
        address[] memory _nfts,
        uint256[] memory _tokenIds,
        uint256[] memory _amounts,
        bool[] memory _toDeposit
    ) external payable nonReentrant whenNotPaused {
        require(
            _nfts.length > 0,
            "nftPool: nft length is zero"
        );

        require(
            _nfts.length == _tokenIds.length &&
            _nfts.length == _amounts.length &&
            _nfts.length == _toDeposit.length,
            "nftPool: array length not equal"
        );

        address user = msg.sender;
        for (uint i = 0; i < _nfts.length; i++) {
            (, bool refinanced) = getTokenStatus(
                user,
                _nfts[i],
                _tokenIds[i]
            );
            require(refinanced, "nftPool: token not refinanced");
        }

        // calculate debt value of NFTs
        uint256 totalDebt;
        for (uint256 i = 0; i < _nfts.length; i++) {
            (, , , uint256 debt, , ) = lendPool.getNftDebtData(
                _nfts[i],
                _tokenIds[i]
            );
            require(_amounts[i] >= debt, "NftPool: repay amount not enough");
            totalDebt += debt;
        }
        require(msg.value >= totalDebt, "NftPool: msg value not enough");
        (uint256[] memory repayAmounts, ) = bendWETHGateway.batchRepayETH{
            value: msg.value
        }(_nfts, _tokenIds, _amounts);

        uint256 totalRepayAmount;
        for (uint256 i = 0; i < repayAmounts.length; i++) {
            totalRepayAmount += repayAmounts[i];
        }
        uint256 remainETHAmount = msg.value - totalRepayAmount;

        // if NFTs need to deposit in Pool
        (address[] memory nfts, uint256[][] memory tokenIds) = _toDepositParams(
            _nfts,
            _tokenIds,
            _toDeposit
        );
        if (nfts.length > 0) {
            uint256 crossChainFee = crossChainContract.estimateDepositFee(
                user,
                nfts,
                tokenIds
            );
            require(
                remainETHAmount >= crossChainFee,
                "NftPool: crossChain fee not enough"
            );
            _deposit(user, nfts, tokenIds, false);

            crossChainContract.sendDepositNftMsg{value: crossChainFee}(
                payable(user),
                nfts,
                tokenIds
            );

            remainETHAmount = remainETHAmount - crossChainFee;
        }

        if (remainETHAmount > 0) {
            _safeTransferETH(user, remainETHAmount);
        }

        // if NFTs don't need to deposit in Pool, return to user
        // update token info in nftsForUser array
        for (uint256 i = 0; i < _nfts.length; i++) {
            address nft = _nfts[i];
            uint256 tokenId = _tokenIds[i];
            TokenRefinanceInfo[] storage tokenRefinanceInfos = nftsForUser[user][nft];
            for (uint256 m = 0; m < tokenRefinanceInfos.length; m++) {
                if (tokenRefinanceInfos[m].tokenId == tokenId) {
                    if (_toDeposit[i]){
                        tokenRefinanceInfos[m].hasRefinanced = false;
                    }else{
                        IERC721Upgradeable(nft).safeTransferFrom(
                            address(this),
                            user,
                            tokenId
                        );
                        tokenRefinanceInfos[m] = tokenRefinanceInfos[
                            tokenRefinanceInfos.length - 1
                        ];
                        tokenRefinanceInfos.pop();
                    }
                }
            }
        }
    }

    function _toDepositParams(
        address[] memory _nftAssets,
        uint256[] memory _nftTokenIds,
        bool[] memory _toDeposit
    ) internal pure returns (address[] memory, uint256[][] memory) {
        address[] memory assetsToDeposit = new address[](_nftAssets.length);
        uint256[][] memory tokenIdsToDeposit = new uint256[][](
            _nftAssets.length
        );
        uint256[] memory indices = new uint256[](_nftAssets.length);
        uint256 count = 0;

        for (uint256 i = 0; i < _toDeposit.length; i++) {
            if (_toDeposit[i]) {
                bool assetFound = false;
                for (uint256 j = 0; j < count; j++) {
                    if (assetsToDeposit[j] == _nftAssets[i]) {
                        tokenIdsToDeposit[j][indices[j]] = _nftTokenIds[i];
                        indices[j]++;
                        assetFound = true;
                        break;
                    }
                }

                if (!assetFound) {
                    assetsToDeposit[count] = _nftAssets[i];
                    tokenIdsToDeposit[count] = new uint256[](_nftAssets.length);
                    tokenIdsToDeposit[count][0] = _nftTokenIds[i];
                    indices[count] = 1;
                    count++;
                }
            }
        }

        address[] memory finalAssets = new address[](count);
        uint256[][] memory finalTokenIds = new uint256[][](count);
        for (uint256 i = 0; i < count; i++) {
            finalAssets[i] = assetsToDeposit[i];
            uint256[] memory ids = new uint256[](indices[i]);
            for (uint256 j = 0; j < indices[i]; j++) {
                ids[j] = tokenIdsToDeposit[i][j];
            }
            finalTokenIds[i] = ids;
        }
        return (finalAssets, finalTokenIds);
    }

    function getNftDebtData(
        address[] memory nftAssets,
        uint256[] memory nftTokenIds
    ) public view returns (uint256[] memory) {
        require(
            nftAssets.length == nftTokenIds.length,
            "NftPool: invalid token amount"
        );
        uint256[] memory debts = new uint256[](nftAssets.length);

        for (uint256 i = 0; i < nftAssets.length; i++) {
            (, , , uint256 debt, , ) = lendPool.getNftDebtData(
                nftAssets[i],
                nftTokenIds[i]
            );
            debts[i] =
                debt +
                (debt * repayBufferAmount) /
                Constants.PERCENTAGE_FACTOR;
        }
        return debts;
    }

    function getTokenStatus(
        address _user,
        address _nft,
        uint256 _tokenId
    ) public view returns (bool, bool) {
        TokenRefinanceInfo[] memory tokenRefinanceInfos = nftsForUser[_user][
            _nft
        ];
        bool tokenInPool;
        bool tokenRefinanced;
        for (uint256 i = 0; i < tokenRefinanceInfos.length; i++) {
            if (tokenRefinanceInfos[i].tokenId == _tokenId) {
                tokenInPool = true;
                if (tokenRefinanceInfos[i].hasRefinanced) {
                    tokenRefinanced = true;
                }
            }
        }
        return (tokenInPool, tokenRefinanced);
    }

    function _safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, "ETH_TRANSFER_FAILED");
    }
}
