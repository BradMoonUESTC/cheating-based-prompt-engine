// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../../../interfaces/IPMarketV3.sol";
import "../../../interfaces/IPYieldContractFactory.sol";
import "../../../interfaces/IPMarketFactoryV3.sol";

import "../../libraries/BaseSplitCodeFactory.sol";
import "../../libraries/Errors.sol";
import "../../libraries/BoringOwnableUpgradeable.sol";

contract PendleMarketFactoryV3 is BoringOwnableUpgradeable, IPMarketFactoryV3 {
    using EnumerableSet for EnumerableSet.AddressSet;

    address public immutable marketCreationCodeContractA;
    uint256 public immutable marketCreationCodeSizeA;
    address public immutable marketCreationCodeContractB;
    uint256 public immutable marketCreationCodeSizeB;

    address public immutable yieldContractFactory;
    address public immutable vePendle;
    address public immutable gaugeController;

    uint256 public immutable maxLnFeeRateRoot;
    uint8 public constant maxReserveFeePercent = 100;
    int256 public constant minInitialAnchor = PMath.IONE;

    address public treasury;
    uint8 public reserveFeePercent;

    // router -> market -> lnFeeRateRoot. lnFeeRateRoot == 0 means no override
    mapping(address => mapping(address => uint80)) internal overriddenFee;

    // PT -> scalarRoot -> initialAnchor
    mapping(address => mapping(int256 => mapping(int256 => mapping(uint80 => address)))) internal markets;
    EnumerableSet.AddressSet internal allMarkets;

    constructor(
        address _yieldContractFactory,
        address _marketCreationCodeContractA,
        uint256 _marketCreationCodeSizeA,
        address _marketCreationCodeContractB,
        uint256 _marketCreationCodeSizeB,
        address _treasury,
        uint8 _reserveFeePercent,
        address _vePendle,
        address _gaugeController
    ) initializer {
        yieldContractFactory = _yieldContractFactory;
        maxLnFeeRateRoot = uint256(LogExpMath.ln(int256((105 * PMath.IONE) / 100))); // ln(1.05)

        marketCreationCodeContractA = _marketCreationCodeContractA;
        marketCreationCodeSizeA = _marketCreationCodeSizeA;
        marketCreationCodeContractB = _marketCreationCodeContractB;
        marketCreationCodeSizeB = _marketCreationCodeSizeB;

        __BoringOwnable_init();
        setTreasuryAndFeeReserve(_treasury, _reserveFeePercent);

        vePendle = _vePendle;
        gaugeController = _gaugeController;
    }

    /**
     * @notice Create a market between PT and its corresponding SY with scalar & anchor config.
     * Anyone is allowed to create a market on their own.
     */
    function createNewMarket(
        address PT,
        int256 scalarRoot,
        int256 initialAnchor,
        uint80 lnFeeRateRoot
    ) external returns (address market) {
        if (!IPYieldContractFactory(yieldContractFactory).isPT(PT)) revert Errors.MarketFactoryInvalidPt();
        if (IPPrincipalToken(PT).isExpired()) revert Errors.MarketFactoryExpiredPt();
        if (lnFeeRateRoot > maxLnFeeRateRoot)
            revert Errors.MarketFactoryLnFeeRateRootTooHigh(lnFeeRateRoot, maxLnFeeRateRoot);

        if (markets[PT][scalarRoot][initialAnchor][lnFeeRateRoot] != address(0))
            revert Errors.MarketFactoryMarketExists();

        if (initialAnchor < minInitialAnchor)
            revert Errors.MarketFactoryInitialAnchorTooLow(initialAnchor, minInitialAnchor);

        market = BaseSplitCodeFactory._create2(
            0,
            bytes32(block.chainid),
            abi.encode(PT, scalarRoot, initialAnchor, lnFeeRateRoot, vePendle, gaugeController),
            marketCreationCodeContractA,
            marketCreationCodeSizeA,
            marketCreationCodeContractB,
            marketCreationCodeSizeB
        );

        markets[PT][scalarRoot][initialAnchor][lnFeeRateRoot] = market;

        if (!allMarkets.add(market)) assert(false);

        emit CreateNewMarket(market, PT, scalarRoot, initialAnchor, lnFeeRateRoot);
    }

    function getMarketConfig(
        address market,
        address router
    ) external view returns (address _treasury, uint80 _overriddenFee, uint8 _reserveFeePercent) {
        (_treasury, _reserveFeePercent) = (treasury, reserveFeePercent);
        _overriddenFee = overriddenFee[router][market];
    }

    /// @dev for gas-efficient verification of market
    function isValidMarket(address market) external view returns (bool) {
        return allMarkets.contains(market);
    }

    function setTreasuryAndFeeReserve(address newTreasury, uint8 newReserveFeePercent) public onlyOwner {
        if (newTreasury == address(0)) revert Errors.MarketFactoryZeroTreasury();
        if (newReserveFeePercent > maxReserveFeePercent)
            revert Errors.MarketFactoryReserveFeePercentTooHigh(newReserveFeePercent, maxReserveFeePercent);

        treasury = newTreasury;
        reserveFeePercent = newReserveFeePercent;

        emit NewTreasuryAndFeeReserve(newTreasury, newReserveFeePercent);
    }

    function setOverriddenFee(address router, address market, uint80 newFee) public onlyOwner {
        if (!allMarkets.contains(market)) revert Errors.MFNotPendleMarket(market);

        uint80 marketFee = IPMarketV3(market).getNonOverrideLnFeeRateRoot();
        if (newFee >= marketFee) revert Errors.MarketFactoryOverriddenFeeTooHigh(newFee, marketFee);

        // NOTE: newFee = 0 allowed !!
        overriddenFee[router][market] = newFee;
        emit SetOverriddenFee(router, market, newFee);
    }
}
