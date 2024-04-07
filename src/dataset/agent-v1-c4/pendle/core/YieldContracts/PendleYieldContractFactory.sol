// SPDX-License-Identifier: GPL-3.0-or-later
/*
 * MIT License
 * ===========
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 */

pragma solidity ^0.8.17;

import "../../interfaces/IPYieldContractFactory.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../libraries/ExpiryUtilsLib.sol";
import "../libraries/BaseSplitCodeFactory.sol";
import "../libraries/MiniHelpers.sol";
import "../libraries/Errors.sol";
import "../libraries/BoringOwnableUpgradeable.sol";
import "../libraries/StringLib.sol";

import "./PendlePrincipalToken.sol";
import "./PendleYieldToken.sol";

/// @dev If this contract is ever made upgradeable, please pay attention to the numContractDeployed variable
contract PendleYieldContractFactory is BoringOwnableUpgradeable, IPYieldContractFactory {
    using ExpiryUtils for string;
    using StringLib for string;
    using StringLib for StringLib.slice;

    string private constant PT_PREFIX = "PT";
    string private constant YT_PREFIX = "YT";
    string private constant SY_SYMBOL_PREF = "SY-";
    string private constant SY_NAME_PREF = "SY ";

    address public immutable ytCreationCodeContractA;
    uint256 public immutable ytCreationCodeSizeA;
    address public immutable ytCreationCodeContractB;
    uint256 public immutable ytCreationCodeSizeB;

    // 1 SLOT
    uint128 public interestFeeRate; // a fixed point number
    uint128 public rewardFeeRate; // a fixed point number

    // 1 SLOT
    address public treasury;
    uint96 public expiryDivisor;

    // SY => expiry => address
    // returns address(0) if not created
    mapping(address => mapping(uint256 => address)) public getPT;
    mapping(address => mapping(uint256 => address)) public getYT;
    mapping(address => bool) public isPT;
    mapping(address => bool) public isYT;

    uint256 public constant maxInterestFeeRate = 2e17; // 20%
    uint256 public constant maxRewardFeeRate = 2e17; // 20%

    constructor(
        address _ytCreationCodeContractA,
        uint256 _ytCreationCodeSizeA,
        address _ytCreationCodeContractB,
        uint256 _ytCreationCodeSizeB
    ) {
        ytCreationCodeContractA = _ytCreationCodeContractA;
        ytCreationCodeSizeA = _ytCreationCodeSizeA;
        ytCreationCodeContractB = _ytCreationCodeContractB;
        ytCreationCodeSizeB = _ytCreationCodeSizeB;
    }

    function initialize(
        uint96 _expiryDivisor,
        uint128 _interestFeeRate,
        uint128 _rewardFeeRate,
        address _treasury
    ) external initializer {
        __BoringOwnable_init();
        setExpiryDivisor(_expiryDivisor);
        setInterestFeeRate(_interestFeeRate);
        setRewardFeeRate(_rewardFeeRate);
        setTreasury(_treasury);
    }

    /**
     * @notice Create a pair of (PT, YT) from any SY and valid expiry. Anyone can create a yield contract
     * @dev It's intentional to make expiry an uint32 to guard against fat fingers. uint32.max is year 2106
     */
    function createYieldContract(
        address SY,
        uint32 expiry,
        bool doCacheIndexSameBlock
    ) external returns (address PT, address YT) {
        if (MiniHelpers.isTimeInThePast(expiry) || expiry % expiryDivisor != 0) revert Errors.YCFactoryInvalidExpiry();

        if (getPT[SY][expiry] != address(0)) revert Errors.YCFactoryYieldContractExisted();

        IStandardizedYield _SY = IStandardizedYield(SY);

        (, , uint8 assetDecimals) = _SY.assetInfo();

        string memory syCoreName = _stripSYPrefix(_SY.name());
        string memory syCoreSymbol = _stripSYPrefix(_SY.symbol());

        PT = Create2.deploy(
            0,
            bytes32(block.chainid),
            abi.encodePacked(
                type(PendlePrincipalToken).creationCode,
                abi.encode(
                    SY,
                    PT_PREFIX.concat(syCoreName, expiry, " "),
                    PT_PREFIX.concat(syCoreSymbol, expiry, "-"),
                    assetDecimals,
                    expiry
                )
            )
        );

        YT = BaseSplitCodeFactory._create2(
            0,
            bytes32(block.chainid),
            abi.encode(
                SY,
                PT,
                YT_PREFIX.concat(syCoreName, expiry, " "),
                YT_PREFIX.concat(syCoreSymbol, expiry, "-"),
                assetDecimals,
                expiry,
                doCacheIndexSameBlock
            ),
            ytCreationCodeContractA,
            ytCreationCodeSizeA,
            ytCreationCodeContractB,
            ytCreationCodeSizeB
        );

        IPPrincipalToken(PT).initialize(YT);

        getPT[SY][expiry] = PT;
        getYT[SY][expiry] = YT;
        isPT[PT] = true;
        isYT[YT] = true;

        emit CreateYieldContract(SY, expiry, PT, YT);
    }

    function setExpiryDivisor(uint96 newExpiryDivisor) public onlyOwner {
        if (newExpiryDivisor == 0) revert Errors.YCFactoryZeroExpiryDivisor();

        expiryDivisor = newExpiryDivisor;
        emit SetExpiryDivisor(newExpiryDivisor);
    }

    function setInterestFeeRate(uint128 newInterestFeeRate) public onlyOwner {
        if (newInterestFeeRate > maxInterestFeeRate)
            revert Errors.YCFactoryInterestFeeRateTooHigh(newInterestFeeRate, maxInterestFeeRate);

        interestFeeRate = newInterestFeeRate;
        emit SetInterestFeeRate(newInterestFeeRate);
    }

    function setRewardFeeRate(uint128 newRewardFeeRate) public onlyOwner {
        if (newRewardFeeRate > maxRewardFeeRate)
            revert Errors.YCFactoryRewardFeeRateTooHigh(newRewardFeeRate, maxRewardFeeRate);

        rewardFeeRate = newRewardFeeRate;
        emit SetRewardFeeRate(newRewardFeeRate);
    }

    function setTreasury(address newTreasury) public onlyOwner {
        if (newTreasury == address(0)) revert Errors.YCFactoryZeroTreasury();

        treasury = newTreasury;
        emit SetTreasury(newTreasury);
    }

    function _stripSYPrefix(string memory _str) internal pure returns (string memory) {
        StringLib.slice memory str = _str.toSlice();
        StringLib.slice memory delim_name = SY_NAME_PREF.toSlice();
        StringLib.slice memory delim_symbol = SY_SYMBOL_PREF.toSlice();
        return str.beyond(delim_name).beyond(delim_symbol).toString();
    }
}
