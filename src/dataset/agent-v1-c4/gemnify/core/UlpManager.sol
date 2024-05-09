// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {IERC20Upgradeable, SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IVault} from "./interfaces/IVault.sol";
import {IUlpManager} from "./interfaces/IUlpManager.sol";
import {IShortsTracker} from "./interfaces/IShortsTracker.sol";
import {IETHG} from "../tokens/interfaces/IETHG.sol";
import {IMintable} from "../tokens/interfaces/IMintable.sol";

import {Constants} from "./libraries/helpers/Constants.sol";
import {DataTypes} from "./libraries/types/DataTypes.sol";

contract UlpManager is
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    IUlpManager
{
    using MathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IVault public override vault;
    IShortsTracker public shortsTracker;
    address public override ethg;
    address public override ulp;

    uint256 public override cooldownDuration;
    mapping(address => uint256) public override lastAddedAt;

    uint256 public aumAddition;
    uint256 public aumDeduction;

    bool public inPrivateMode;
    uint256 public shortsTrackerAveragePriceWeight;
    mapping(address => bool) public isHandler;

    event AddLiquidity(
        address account,
        address token,
        uint256 amount,
        uint256 aumInEthg,
        uint256 ulpSupply,
        uint256 ethgAmount,
        uint256 mintAmount
    );

    event AddLiquidityNFT(
        address account,
        address nft,
        uint256 tokenId,
        uint256 aumInEthg,
        uint256 ulpSupply,
        uint256 ethgAmount,
        uint256 mintAmount
    );

    event RemoveLiquidity(
        address account,
        address token,
        uint256 ulpAmount,
        uint256 aumInEthg,
        uint256 ulpSupply,
        uint256 ethgAmount,
        uint256 amountOut
    );

    function initialize(
        address _vault,
        address _ethg,
        address _ulp,
        address _shortsTracker,
        uint256 _cooldownDuration
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        vault = IVault(_vault);
        ethg = _ethg;
        ulp = _ulp;
        shortsTracker = IShortsTracker(_shortsTracker);
        cooldownDuration = _cooldownDuration;
    }

    function setInPrivateMode(bool _inPrivateMode) external onlyOwner {
        inPrivateMode = _inPrivateMode;
    }

    function setShortsTracker(
        IShortsTracker _shortsTracker
    ) external onlyOwner {
        shortsTracker = _shortsTracker;
    }

    function setShortsTrackerAveragePriceWeight(
        uint256 _shortsTrackerAveragePriceWeight
    ) external override onlyOwner {
        require(
            shortsTrackerAveragePriceWeight <= Constants.PERCENTAGE_FACTOR,
            "UlpManager: invalid weight"
        );
        shortsTrackerAveragePriceWeight = _shortsTrackerAveragePriceWeight;
    }

    function setHandler(address _handler, bool _isActive) external onlyOwner {
        isHandler[_handler] = _isActive;
    }

    function setCooldownDuration(
        uint256 _cooldownDuration
    ) external override onlyOwner {
        require(
            _cooldownDuration <= Constants.MAX_COOLDOWN_DURATION,
            "UlpManager: invalid _cooldownDuration"
        );
        cooldownDuration = _cooldownDuration;
    }

    function setAumAdjustment(
        uint256 _aumAddition,
        uint256 _aumDeduction
    ) external onlyOwner {
        aumAddition = _aumAddition;
        aumDeduction = _aumDeduction;
    }

    function addLiquidity(
        address _token,
        uint256 _amount,
        uint256 _minEthg,
        uint256 _minUlp
    ) external override nonReentrant returns (uint256) {
        if (inPrivateMode) {
            revert("UlpManager: action not enabled");
        }
        return
            _addLiquidity(
                msg.sender,
                msg.sender,
                _token,
                _amount,
                _minEthg,
                _minUlp
            );
    }

    function addLiquidityForAccount(
        address _fundingAccount,
        address _account,
        address _token,
        uint256 _amount,
        uint256 _minEthg,
        uint256 _minUlp
    ) external override nonReentrant returns (uint256) {
        _validateHandler();
        return
            _addLiquidity(
                _fundingAccount,
                _account,
                _token,
                _amount,
                _minEthg,
                _minUlp
            );
    }

    function addLiquidityNFTForAccount(
        address _fundingAccount,
        address _account,
        address _nft,
        uint256 _tokenId,
        uint256 _minEthg,
        uint256 _minUlp
    ) external override nonReentrant returns (uint256) {
        _validateHandler();
        return
            _addLiquidityNFT(
                _fundingAccount,
                _account,
                _nft,
                _tokenId,
                _minEthg,
                _minUlp
            );
    }

    function removeLiquidity(
        address _tokenOut,
        uint256 _ulpAmount,
        uint256 _minOut,
        address _receiver
    ) external override nonReentrant returns (uint256) {
        if (inPrivateMode) {
            revert("UlpManager: action not enabled");
        }
        return
            _removeLiquidity(
                msg.sender,
                _tokenOut,
                _ulpAmount,
                _minOut,
                _receiver
            );
    }

    function removeLiquidityForAccount(
        address _account,
        address _tokenOut,
        uint256 _ulpAmount,
        uint256 _minOut,
        address _receiver
    ) external override nonReentrant returns (uint256) {
        _validateHandler();
        return
            _removeLiquidity(
                _account,
                _tokenOut,
                _ulpAmount,
                _minOut,
                _receiver
            );
    }

    function removeLiquidityNFTForAccount(
        address _account,
        address _nft,
        uint256 _tokenId,
        address _weth,
        uint256 _ethAmount,
        uint256 _ulpAmount,
        address _receiver
    ) external override nonReentrant returns (uint256) {
        _validateHandler();
        return
            _removeLiquidityNFT(
                _account,
                _nft,
                _tokenId,
                _weth,
                _ethAmount,
                _ulpAmount,
                _receiver
            );
    }

    function getPrice(bool _maximise) public view override returns (uint256) {
        uint256 aum = getAum(_maximise);
        uint256 supply = IERC20Upgradeable(ulp).totalSupply();
        return (aum * Constants.ULP_PRECISION) / supply;
    }

    function getAums() public view returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = getAum(true);
        amounts[1] = getAum(false);
        return amounts;
    }

    function getAumInEthg(
        bool maximise
    ) public view override returns (uint256) {
        uint256 aum = getAum(maximise);
        return
            (aum * 10 ** Constants.ETHG_DECIMALS) / Constants.PRICE_PRECISION;
    }

    function getAum(bool maximise) public view override returns (uint256) {
        (uint256 length, address[] memory allWhitelistedTokens) = vault
            .getWhitelistedToken();
        uint256 aum = aumAddition;
        uint256 shortProfits = 0;
        IVault _vault = vault;

        for (uint256 i = 0; i < length; i++) {
            address token = allWhitelistedTokens[i];
            DataTypes.TokenInfo memory tokenInfo = vault.getTokenInfo(token);

            if (!tokenInfo.isWhitelistedToken) {
                continue;
            }

            uint256 price = maximise
                ? _vault.getMaxPrice(token)
                : _vault.getMinPrice(token);
            (
                uint256 poolAmount,
                uint256 reservedAmount,
                ,
                uint256 guaranteedEth,
                uint256 size,
                ,

            ) = vault.getPoolInfo(token);

            if (tokenInfo.isStableToken) {
                aum =
                    aum +
                    ((poolAmount * price) / 10 ** tokenInfo.tokenDecimal);
            } else {
                if (tokenInfo.isNftToken) {
                    uint256 priceBend = _vault.getBendDAOAssetPrice(token);
                    price = price < priceBend ? price : priceBend;
                }
                // add global short profit / loss
                //uint256 size = globalShortSize;

                if (size > 0) {
                    (uint256 delta, bool hasProfit) = getGlobalShortDelta(
                        token,
                        price,
                        size
                    );
                    if (!hasProfit) {
                        // add losses from shorts
                        aum = aum + delta;
                    } else {
                        shortProfits = shortProfits + delta;
                    }
                }

                aum = aum + guaranteedEth;

                aum =
                    aum +
                    ((poolAmount - reservedAmount) * price) /
                    10 ** tokenInfo.tokenDecimal;
            }
        }

        aum = shortProfits > aum ? 0 : aum - shortProfits;
        return aumDeduction > aum ? 0 : aum - aumDeduction;
    }

    function getGlobalShortDelta(
        address _token,
        uint256 _price,
        uint256 _size
    ) public view returns (uint256, bool) {
        uint256 averagePrice = getGlobalShortAveragePrice(_token);
        uint256 priceDelta = averagePrice > _price
            ? averagePrice - _price
            : _price - averagePrice;
        uint256 delta = (_size * priceDelta) / averagePrice;
        return (delta, averagePrice > _price);
    }

    function getGlobalShortAveragePrice(
        address _token
    ) public view returns (uint256) {
        (, , , , , uint256 globalShortAveragePrice, ) = vault.getPoolInfo(
            _token
        );
        IShortsTracker _shortsTracker = shortsTracker;
        if (
            address(_shortsTracker) == address(0) ||
            !_shortsTracker.isGlobalShortDataReady()
        ) {
            return globalShortAveragePrice;
        }

        uint256 _shortsTrackerAveragePriceWeight = shortsTrackerAveragePriceWeight;
        if (_shortsTrackerAveragePriceWeight == 0) {
            return globalShortAveragePrice;
        } else if (
            _shortsTrackerAveragePriceWeight == Constants.PERCENTAGE_FACTOR
        ) {
            return _shortsTracker.globalShortAveragePrices(_token);
        }

        uint256 vaultAveragePrice = globalShortAveragePrice;
        uint256 shortsTrackerAveragePrice = _shortsTracker
            .globalShortAveragePrices(_token);

        return
            (vaultAveragePrice *
                (Constants.PERCENTAGE_FACTOR -
                    _shortsTrackerAveragePriceWeight) +
                (shortsTrackerAveragePrice *
                    _shortsTrackerAveragePriceWeight)) /
            Constants.PERCENTAGE_FACTOR;
    }

    function _addLiquidity(
        address _fundingAccount,
        address _account,
        address _token,
        uint256 _amount,
        uint256 _minEthg,
        uint256 _minUlp
    ) private returns (uint256) {
        require(_amount > 0, "UlpManager: invalid _amount");

        // calculate aum before buyETHG
        uint256 aumInEthg = getAumInEthg(true);
        uint256 ulpSupply = IERC20Upgradeable(ulp).totalSupply();

        IERC20Upgradeable(_token).safeTransferFrom(
            _fundingAccount,
            address(vault),
            _amount
        );
        uint256 ethgAmount = vault.buyETHG(_token, address(this));
        require(ethgAmount >= _minEthg, "UlpManager: insufficient ETHG output");

        uint256 mintAmount = aumInEthg == 0
            ? ethgAmount
            : (ethgAmount * ulpSupply) / aumInEthg;
        require(mintAmount >= _minUlp, "UlpManager: insufficient ULP output");

        IMintable(ulp).mint(_account, mintAmount);

        lastAddedAt[_account] = block.timestamp;

        emit AddLiquidity(
            _account,
            _token,
            _amount,
            aumInEthg,
            ulpSupply,
            ethgAmount,
            mintAmount
        );

        return mintAmount;
    }

    function _addLiquidityNFT(
        address _fundingAccount,
        address _account,
        address _nft,
        uint256 _tokenId,
        uint256 _minEthg,
        uint256 _minUlp
    ) private returns (uint256) {
        (address certiNft, uint256 ltv) = vault.getNftInfo(_nft);

        require(
            certiNft != address(0) && ltv > 0,
            "UlpManager: nft info illegal"
        );

        // add user nft info
        vault.addNftToUser(_account, _nft, _tokenId);

        // calculate aum before buyETHG
        uint256 aumInEthg = getAumInEthg(true);
        uint256 ulpSupply = IERC20Upgradeable(ulp).totalSupply();

        vault.mintNToken(
            _nft,
            ((ltv * vault.getTokenDecimal(_nft)) / Constants.PERCENTAGE_FACTOR)
        );

        uint256 ethgAmount = vault.buyETHG(_nft, address(this));
        require(ethgAmount >= _minEthg, "UlpManager: insufficient ETHG output");

        uint256 mintAmount = aumInEthg == 0
            ? ethgAmount
            : (ethgAmount * ulpSupply) / aumInEthg;
        require(mintAmount >= _minUlp, "UlpManager: insufficient ULP output");

        IMintable(ulp).mint(_account, mintAmount);

        lastAddedAt[_account] = block.timestamp;

        vault.mintCNft(certiNft, _fundingAccount, _tokenId, ltv);

        emit AddLiquidityNFT(
            _account,
            _nft,
            _tokenId,
            aumInEthg,
            ulpSupply,
            ethgAmount,
            mintAmount
        );

        return mintAmount;
    }

    function _removeLiquidity(
        address _account,
        address _tokenOut,
        uint256 _ulpAmount,
        uint256 _minOut,
        address _receiver
    ) private returns (uint256) {
        require(_ulpAmount > 0, "UlpManager: invalid _ulpAmount");
        require(
            lastAddedAt[_account] + cooldownDuration <= block.timestamp,
            "UlpManager: cooldown duration not yet passed"
        );

        // calculate aum before sellETHG
        uint256 aumInEthg = getAumInEthg(false);
        uint256 ulpSupply = IERC20Upgradeable(ulp).totalSupply();

        uint256 ethgAmount = (_ulpAmount * aumInEthg) / ulpSupply;
        uint256 ethgBalance = IERC20Upgradeable(ethg).balanceOf(address(this));
        if (ethgAmount > ethgBalance) {
            IETHG(ethg).mint(address(this), ethgAmount - ethgBalance);
        }

        IMintable(ulp).burn(_account, _ulpAmount);

        IERC20Upgradeable(ethg).safeTransfer(address(vault), ethgAmount);
        uint256 amountOut = vault.sellETHG(_tokenOut, _receiver);
        require(amountOut >= _minOut, "UlpManager: insufficient output");

        emit RemoveLiquidity(
            _account,
            _tokenOut,
            _ulpAmount,
            aumInEthg,
            ulpSupply,
            ethgAmount,
            amountOut
        );

        return amountOut;
    }

    function isNftDepsoitedForUser(
        address _user,
        address _nft,
        uint256 _tokenId
    ) external view returns (bool) {
        return vault.isNftDepsoitedForUser(_user, _nft, _tokenId);
    }

    function getULPAmountWhenRedeemNft(
        address _nft,
        uint256 _tokenId,
        uint256 _ethAmount
    ) external view override returns (uint256) {
        uint256 aumInEthg = getAumInEthg(true);
        uint256 ulpSupply = IERC20Upgradeable(ulp).totalSupply();

        (uint256 ethgAmount, uint256 feeEthgAmount) = vault
            .getETHGAmountWhenRedeemNft(_nft, _tokenId, _ethAmount);

        uint256 ulpAmount = ((ethgAmount + feeEthgAmount) * ulpSupply) /
            aumInEthg;

        return ulpAmount;
    }

    function _removeLiquidityNFT(
        address _account,
        address _nft,
        uint256 _tokenId,
        address _weth,
        uint256 _ethAmount,
        uint256 _ulpAmount,
        address _receiver
    ) private returns (uint256) {
        require(
            _ulpAmount > 0 || _ethAmount > 0,
            "UlpManager: invalid _amount"
        );
        require(
            lastAddedAt[_account] + cooldownDuration <= block.timestamp,
            "UlpManager: cooldown duration not yet passed"
        );

        (address certiNft, ) = vault.getNftInfo(_nft);

        address owner = IERC721Upgradeable(certiNft).ownerOf(_tokenId);
        require(owner == _receiver, "UlpManager: no certiNft");

        // calculate aum before sellETHG
        uint256 aumInEthg = getAumInEthg(false);
        uint256 ulpSupply = IERC20Upgradeable(ulp).totalSupply();

        // transfer eth from rewardRouter to vault
        IERC20Upgradeable(_weth).safeTransferFrom(
            msg.sender,
            address(vault),
            _ethAmount
        );

        uint256 ethgAmount = (_ulpAmount * aumInEthg) / ulpSupply;
        uint256 ethgBalance = IERC20Upgradeable(ethg).balanceOf(address(this));
        if (ethgAmount > ethgBalance) {
            IETHG(ethg).mint(address(this), ethgAmount - ethgBalance);
        }

        IMintable(ulp).burn(_account, _ulpAmount);
        vault.burnCNft(certiNft, _tokenId);
        IERC20Upgradeable(ethg).safeTransfer(address(vault), ethgAmount);
        vault.sellETHG(_nft, _receiver);

        // remove nft from user
        vault.removeNftFromUser(_account, _nft, _tokenId);

        return 0;
    }

    function _validateHandler() private view {
        require(isHandler[msg.sender], "UlpManager: forbidden");
    }
}
