// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../../../interfaces/IPMarket.sol";
import "../../../interfaces/IPMarketFactory.sol";
import "../../../interfaces/IPMarketSwapCallback.sol";

import "../../erc20/PendleERC20.sol";
import "../PendleGauge.sol";
import "../OracleLib.sol";

/**
Invariance to maintain:
- Internal balances totalPt & totalSy not interfered by people transferring tokens in directly
- address(0) & address(this) should never have any rewards & activeBalance accounting done. This is
    guaranteed by address(0) & address(this) check in each updateForTwo function
*/
contract PendleMarket is PendleERC20, PendleGauge, IPMarket {
    using PMath for uint256;
    using PMath for int256;
    using MarketMathCore for MarketState;
    using SafeERC20 for IERC20;
    using PYIndexLib for IPYieldToken;
    using OracleLib for OracleLib.Observation[65535];

    struct MarketStorage {
        int128 totalPt;
        int128 totalSy;
        // 1 SLOT = 256 bits
        uint96 lastLnImpliedRate;
        uint16 observationIndex;
        uint16 observationCardinality;
        uint16 observationCardinalityNext;
        // 1 SLOT = 144 bits
    }

    string private constant NAME = "Pendle Market";
    string private constant SYMBOL = "PENDLE-LPT";

    IPPrincipalToken internal immutable PT;
    IStandardizedYield internal immutable SY;
    IPYieldToken internal immutable YT;

    address public immutable factory;
    uint256 public immutable expiry;
    int256 public immutable scalarRoot;
    int256 public immutable initialAnchor;

    MarketStorage public _storage;

    OracleLib.Observation[65535] public observations;

    modifier notExpired() {
        if (isExpired()) revert Errors.MarketExpired();
        _;
    }

    constructor(
        address _PT,
        int256 _scalarRoot,
        int256 _initialAnchor,
        address _vePendle,
        address _gaugeController
    ) PendleERC20(NAME, SYMBOL, 18) PendleGauge(IPPrincipalToken(_PT).SY(), _vePendle, _gaugeController) {
        PT = IPPrincipalToken(_PT);
        SY = IStandardizedYield(PT.SY());
        YT = IPYieldToken(PT.YT());

        (_storage.observationCardinality, _storage.observationCardinalityNext) = observations.initialize(
            uint32(block.timestamp)
        );

        if (_scalarRoot <= 0) revert Errors.MarketScalarRootBelowZero(_scalarRoot);

        scalarRoot = _scalarRoot;
        initialAnchor = _initialAnchor;
        expiry = IPPrincipalToken(_PT).expiry();
        factory = msg.sender;
    }

    /**
     * @notice PendleMarket allows users to provide in PT & SY in exchange for LPs, which
     * will grant LP holders more exchange fee over time
     * @dev will mint as much LP as possible such that the corresponding SY and PT used do
     * not exceed `netSyDesired` and `netPtDesired`, respectively
     * @dev PT and SY should be transferred to this contract prior to calling
     * @dev will revert if PT is expired
     */
    function mint(
        address receiver,
        uint256 netSyDesired,
        uint256 netPtDesired
    ) external nonReentrant notExpired returns (uint256 netLpOut, uint256 netSyUsed, uint256 netPtUsed) {
        MarketState memory market = readState(msg.sender);
        PYIndex index = YT.newIndex();

        uint256 lpToReserve;

        (lpToReserve, netLpOut, netSyUsed, netPtUsed) = market.addLiquidity(
            netSyDesired,
            netPtDesired,
            block.timestamp
        );

        // initializing the market
        if (lpToReserve != 0) {
            market.setInitialLnImpliedRate(index, initialAnchor, block.timestamp);
            _mint(address(1), lpToReserve);
        }

        _mint(receiver, netLpOut);

        _writeState(market);

        if (_selfBalance(SY) < market.totalSy.Uint())
            revert Errors.MarketInsufficientSyReceived(_selfBalance(SY), market.totalSy.Uint());
        if (_selfBalance(PT) < market.totalPt.Uint())
            revert Errors.MarketInsufficientPtReceived(_selfBalance(PT), market.totalPt.Uint());

        emit Mint(receiver, netLpOut, netSyUsed, netPtUsed);
    }

    /**
     * @notice LP Holders can burn their LP to receive back SY & PT proportionally
     * to their share of the market
     */
    function burn(
        address receiverSy,
        address receiverPt,
        uint256 netLpToBurn
    ) external nonReentrant returns (uint256 netSyOut, uint256 netPtOut) {
        MarketState memory market = readState(msg.sender);

        _burn(address(this), netLpToBurn);

        (netSyOut, netPtOut) = market.removeLiquidity(netLpToBurn);

        if (receiverSy != address(this)) IERC20(SY).safeTransfer(receiverSy, netSyOut);
        if (receiverPt != address(this)) IERC20(PT).safeTransfer(receiverPt, netPtOut);

        _writeState(market);

        emit Burn(receiverSy, receiverPt, netLpToBurn, netSyOut, netPtOut);
    }

    /**
     * @notice Pendle Market allows swaps between PT & SY it is holding. This function
     * aims to swap an exact amount of PT to SY.
     * @dev steps working of this contract
       - The outcome amount of SY will be precomputed by MarketMathLib
       - Release the calculated amount of SY to receiver
       - Callback to msg.sender if data.length > 0
       - Ensure exactPtIn amount of PT has been transferred to this address
     * @dev will revert if PT is expired
     * @param data bytes data to be sent in the callback (if any)
     */
    function swapExactPtForSy(
        address receiver,
        uint256 exactPtIn,
        bytes calldata data
    ) external nonReentrant notExpired returns (uint256 netSyOut, uint256 netSyFee) {
        MarketState memory market = readState(msg.sender);

        uint256 netSyToReserve;
        (netSyOut, netSyFee, netSyToReserve) = market.swapExactPtForSy(YT.newIndex(), exactPtIn, block.timestamp);

        if (receiver != address(this)) IERC20(SY).safeTransfer(receiver, netSyOut);
        IERC20(SY).safeTransfer(market.treasury, netSyToReserve);

        _writeState(market);

        if (data.length > 0) {
            IPMarketSwapCallback(msg.sender).swapCallback(exactPtIn.neg(), netSyOut.Int(), data);
        }

        if (_selfBalance(PT) < market.totalPt.Uint())
            revert Errors.MarketInsufficientPtReceived(_selfBalance(PT), market.totalPt.Uint());

        emit Swap(msg.sender, receiver, exactPtIn.neg(), netSyOut.Int(), netSyFee, netSyToReserve);
    }

    /**
     * @notice Pendle Market allows swaps between PT & SY it is holding. This function
     * aims to swap SY for an exact amount of PT.
     * @dev steps working of this function
       - The exact outcome amount of PT will be transferred to receiver
       - Callback to msg.sender if data.length > 0
       - Ensure the calculated required amount of SY is transferred to this address
     * @dev will revert if PT is expired
     * @param data bytes data to be sent in the callback (if any)
     */
    function swapSyForExactPt(
        address receiver,
        uint256 exactPtOut,
        bytes calldata data
    ) external nonReentrant notExpired returns (uint256 netSyIn, uint256 netSyFee) {
        MarketState memory market = readState(msg.sender);

        uint256 netSyToReserve;
        (netSyIn, netSyFee, netSyToReserve) = market.swapSyForExactPt(YT.newIndex(), exactPtOut, block.timestamp);

        if (receiver != address(this)) IERC20(PT).safeTransfer(receiver, exactPtOut);
        IERC20(SY).safeTransfer(market.treasury, netSyToReserve);

        _writeState(market);

        if (data.length > 0) {
            IPMarketSwapCallback(msg.sender).swapCallback(exactPtOut.Int(), netSyIn.neg(), data);
        }

        // have received enough SY
        if (_selfBalance(SY) < market.totalSy.Uint())
            revert Errors.MarketInsufficientSyReceived(_selfBalance(SY), market.totalSy.Uint());

        emit Swap(msg.sender, receiver, exactPtOut.Int(), netSyIn.neg(), netSyFee, netSyToReserve);
    }

    /// @notice forces balances to match reserves
    function skim() external nonReentrant {
        MarketState memory market = readState(msg.sender);
        uint256 excessPt = _selfBalance(PT) - market.totalPt.Uint();
        uint256 excessSy = _selfBalance(SY) - market.totalSy.Uint();
        if (excessPt != 0) IERC20(PT).safeTransfer(market.treasury, excessPt);
        if (excessSy != 0) IERC20(SY).safeTransfer(market.treasury, excessSy);
    }

    /**
     * @notice redeems the user's reward
     * @return amount of reward token redeemed, in the same order as `getRewardTokens()`
     */
    function redeemRewards(address user) external nonReentrant returns (uint256[] memory) {
        return _redeemRewards(user);
    }

    /// @notice returns the list of reward tokens
    function getRewardTokens() external view returns (address[] memory) {
        return _getRewardTokens();
    }

    /*///////////////////////////////////////////////////////////////
                                ORACLE
    //////////////////////////////////////////////////////////////*/

    function observe(uint32[] memory secondsAgos) external view returns (uint216[] memory lnImpliedRateCumulative) {
        return
            observations.observe(
                uint32(block.timestamp),
                secondsAgos,
                _storage.lastLnImpliedRate,
                _storage.observationIndex,
                _storage.observationCardinality
            );
    }

    function increaseObservationsCardinalityNext(uint16 cardinalityNext) external nonReentrant {
        uint16 cardinalityNextOld = _storage.observationCardinalityNext;
        uint16 cardinalityNextNew = observations.grow(cardinalityNextOld, cardinalityNext);
        if (cardinalityNextOld != cardinalityNextNew) {
            _storage.observationCardinalityNext = cardinalityNextNew;
            emit IncreaseObservationCardinalityNext(cardinalityNextOld, cardinalityNextNew);
        }
    }

    /*///////////////////////////////////////////////////////////////
                                READ/WRITE STATES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice read the state of the market from storage into memory for gas-efficient manipulation
     */
    function readState(address router) public view returns (MarketState memory market) {
        market.totalPt = _storage.totalPt;
        market.totalSy = _storage.totalSy;
        market.totalLp = totalSupply().Int();

        (market.treasury, market.lnFeeRateRoot, market.reserveFeePercent) = IPMarketFactory(factory).getMarketConfig(
            router
        );

        market.scalarRoot = scalarRoot;
        market.expiry = expiry;

        market.lastLnImpliedRate = _storage.lastLnImpliedRate;
    }

    /// @notice write back the state of the market from memory to storage
    function _writeState(MarketState memory market) internal {
        uint96 lastLnImpliedRate96 = market.lastLnImpliedRate.Uint96();
        int128 totalPt128 = market.totalPt.Int128();
        int128 totalSy128 = market.totalSy.Int128();

        (uint16 observationIndex, uint16 observationCardinality) = observations.write(
            _storage.observationIndex,
            uint32(block.timestamp),
            _storage.lastLnImpliedRate,
            _storage.observationCardinality,
            _storage.observationCardinalityNext
        );

        _storage.totalPt = totalPt128;
        _storage.totalSy = totalSy128;
        _storage.lastLnImpliedRate = lastLnImpliedRate96;
        _storage.observationIndex = observationIndex;
        _storage.observationCardinality = observationCardinality;

        emit UpdateImpliedRate(block.timestamp, market.lastLnImpliedRate);
    }

    /*///////////////////////////////////////////////////////////////
                            TRIVIAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function readTokens() external view returns (IStandardizedYield _SY, IPPrincipalToken _PT, IPYieldToken _YT) {
        _SY = SY;
        _PT = PT;
        _YT = YT;
    }

    function isExpired() public view returns (bool) {
        return MiniHelpers.isCurrentlyExpired(expiry);
    }

    /*///////////////////////////////////////////////////////////////
                    PENDLE GAUGE - RELATED
    //////////////////////////////////////////////////////////////*/

    function _stakedBalance(address user) internal view override returns (uint256) {
        return balanceOf(user);
    }

    function _totalStaked() internal view override returns (uint256) {
        return totalSupply();
    }

    // solhint-disable-next-line ordering
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(PendleERC20, PendleGauge) {
        PendleGauge._beforeTokenTransfer(from, to, amount);
    }

    // solhint-disable-next-line ordering
    function _afterTokenTransfer(address from, address to, uint256 amount) internal override(PendleERC20, PendleGauge) {
        PendleGauge._afterTokenTransfer(from, to, amount);
    }
}
