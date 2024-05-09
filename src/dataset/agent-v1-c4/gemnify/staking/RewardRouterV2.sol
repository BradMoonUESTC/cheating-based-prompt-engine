// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {IERC20Upgradeable, SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IRewardTracker} from "./interfaces/IRewardTracker.sol";
import {IRewardRouterV2} from "./interfaces/IRewardRouterV2.sol";
import {IMintable} from "../tokens/interfaces/IMintable.sol";
import {IWETH} from "../tokens/interfaces/IWETH.sol";
import {IUlpManager} from "../core/interfaces/IUlpManager.sol";
import {ICrossChain} from "../core/interfaces/ICrossChain.sol";

contract RewardRouterV2 is
    IRewardRouterV2,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable
{
    using MathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public weth;

    address public ulp; // GEMNIFY Liquidity Provider token

    address public override feeUlpTracker;

    address public ulpManager;

    // only cross-chain contract can call stake nft
    ICrossChain public crossChainContract;

    mapping(address => address) public pendingReceivers;
    mapping(address => address) public nftToNftErc20; // nft address ==> nft erc20 token address
    mapping(address => address) public nftErc20ToNft; // nft erc20 token address ==> nft address

    uint256 public crossChainFee;

    event StakeUlpETH(address account, uint256 amount);
    event UnstakeUlpETH(address account, uint256 ulpAmount, uint256 ethAmount);

    event StakeUlpNFT(
        address account,
        uint256 amount,
        address nft,
        uint256 tokenId
    );
    event UnstakeUlpNFT(
        address account,
        uint256 amount,
        address nft,
        uint256 tokenId
    );

    receive() external payable {
        require(msg.sender == weth, "RewardRouter: invalid sender");
    }

    modifier onlyCrossChain() {
        require(
            msg.sender == address(crossChainContract),
            "RewardRouter: not crossChain"
        );
        _;
    }

    function initialize(
        address _weth,
        address _ulp,
        address _feeUlpTracker,
        address _ulpManager
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        weth = _weth;
        ulp = _ulp;
        feeUlpTracker = _feeUlpTracker;
        ulpManager = _ulpManager;
    }

    function setCrossChainAddress(address _addr) external onlyOwner {
        crossChainContract = ICrossChain(_addr);
    }

    function setNftToNftErc20(
        address _nft,
        address _nftErc20
    ) external onlyOwner {
        require(
            _nft != address(0) && _nftErc20 != address(0),
            "rewardRouter: address is zero"
        );
        nftToNftErc20[_nft] = _nftErc20;
        nftErc20ToNft[_nftErc20] = _nft;
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(
        address _token,
        address _account,
        uint256 _amount
    ) external onlyOwner {
        IERC20Upgradeable(_token).safeTransfer(_account, _amount);
    }

    function mintAndStakeUlpETH(
        uint256 _minEthg,
        uint256 _minUlp
    ) external payable nonReentrant returns (uint256) {
        require(msg.value > 0, "RewardRouter: invalid msg.value");

        IWETH(weth).deposit{value: msg.value}();
        IERC20Upgradeable(weth).approve(ulpManager, msg.value);

        address account = msg.sender;
        uint256 ulpAmount = IUlpManager(ulpManager).addLiquidityForAccount(
            address(this),
            account,
            weth,
            msg.value,
            _minEthg,
            _minUlp
        );

        IRewardTracker(feeUlpTracker).stakeForAccount(
            account,
            account,
            ulp,
            ulpAmount
        );

        emit StakeUlpETH(account, ulpAmount);

        return ulpAmount;
    }

    function mintAndStakeUlpNFT(
        address _user,
        address _nft,
        uint256 _tokenId,
        uint256 _minEthg,
        uint256 _minUlp
    ) external nonReentrant onlyCrossChain returns (uint256) {
        address nftErc20 = nftToNftErc20[_nft];
        require(nftErc20 != address(0), "RewardRouter: nft not exist");
        uint256 ulpAmount = IUlpManager(ulpManager).addLiquidityNFTForAccount(
            _user,
            _user,
            nftErc20,
            _tokenId,
            _minEthg,
            _minUlp
        );
        IRewardTracker(feeUlpTracker).stakeForAccount(
            _user,
            _user,
            ulp,
            ulpAmount
        );

        emit StakeUlpNFT(_user, ulpAmount, nftErc20, _tokenId);

        return ulpAmount;
    }

    function unstakeAndRedeemUlpETH(
        uint256 _ulpAmount,
        uint256 _minOut,
        address _receiver
    ) external nonReentrant returns (uint256) {
        require(_ulpAmount > 0, "RewardRouter: invalid _ulpAmount");

        address account = msg.sender;
        IRewardTracker(feeUlpTracker).unstakeForAccount(
            account,
            ulp,
            _ulpAmount,
            account
        );
        uint256 amountOut = IUlpManager(ulpManager).removeLiquidityForAccount(
            account,
            weth,
            _ulpAmount,
            _minOut,
            address(this)
        );

        IWETH(weth).withdraw(amountOut);

        _safeTransferETH(_receiver, amountOut);

        emit UnstakeUlpETH(account, _ulpAmount, amountOut);

        return amountOut;
    }

    function unstakeAndRedeemUlpNFT(
        address[] memory _nfts,
        uint256[][] memory _tokenIds,
        address _receiver
    ) external payable nonReentrant returns (uint256) {
        uint256 estimateCrossChainFee = crossChainContract.estimateWithdrawFee(
            _receiver,
            _nfts,
            _tokenIds
        );
        require(
            msg.value >= estimateCrossChainFee,
            "RewardRouter: estimate CrossChainFee not enough"
        );

        uint256 _tokenId;
        address _nft;
        address[] memory nftsL1 = new address[](_nfts.length);
        uint256 withdrawMsgValue = msg.value - estimateCrossChainFee;
        for (uint256 i = 0; i < _nfts.length; i++) {
            require(_tokenIds[i].length > 0, "RewardRouter: empty tokenIds");
            _nft = _nfts[i];
            for (uint256 j = 0; j < _tokenIds[i].length; j++) {
                _tokenId = _tokenIds[i][j];
                bool b = IUlpManager(ulpManager).isNftDepsoitedForUser(
                    _receiver,
                    _nft,
                    _tokenId
                );
                require(b, "RewardRouter: nft not found");

                uint256 ulpAmount = IUlpManager(ulpManager)
                    .getULPAmountWhenRedeemNft(
                        _nft,
                        _tokenId,
                        withdrawMsgValue
                    );

                IWETH(weth).deposit{value: withdrawMsgValue}();

                IERC20Upgradeable(weth).approve(ulpManager, withdrawMsgValue);

                address account = msg.sender;
                // TODO gas optimization
                IRewardTracker(feeUlpTracker).unstakeForAccount(
                    account,
                    ulp,
                    ulpAmount,
                    account
                );
                IUlpManager(ulpManager).removeLiquidityNFTForAccount(
                    account,
                    _nft,
                    _tokenId,
                    weth,
                    withdrawMsgValue,
                    ulpAmount,
                    account
                );

                emit UnstakeUlpNFT(account, ulpAmount, _nft, _tokenId);
            }
            nftsL1[i] = nftErc20ToNft[_nft];
        }

        crossChainContract.sendWithDrawNftMsg{value: estimateCrossChainFee}(
            payable(_receiver),
            nftsL1,
            _tokenIds
        );
        return 0;
    }

    function handleRewards(
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external nonReentrant {
        address account = msg.sender;

        if (_shouldClaimWeth) {
            if (_shouldConvertWethToEth) {
                uint256 wethAmount = IRewardTracker(feeUlpTracker)
                    .claimForAccount(account, address(this));

                IWETH(weth).withdraw(wethAmount);
                _safeTransferETH(account, wethAmount);
            } else {
                IRewardTracker(feeUlpTracker).claimForAccount(account, account);
            }
        }
    }

    function _safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, "ETH_TRANSFER_FAILED");
    }
}
