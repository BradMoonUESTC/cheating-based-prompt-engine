// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../interfaces/IMemePool.sol";
import "./BaseModule.sol";
import "@openzeppelin-contracts/contracts/mocks/proxy/BadBeacon.sol";

/// Extra Profit Give Token Holder
contract ProfitMiningModule is BaseModule {

    //////////////////////////////// Structs ////////////////////////////////

    struct TradeDetail {
        uint256 holdAmount;
        uint256 principle;
        uint256 rewardDebt;
    }

    /// @dev 1Day: 8.64%  7Day: 60.48%
    uint256 constant public GROWTH_COEFFICIENT = 1E6;
    uint256 constant PRECISION = 1E12;

    // Pool StartTime
    mapping(address => uint256) public startTime;
    // Pool => User => Data
    mapping(address => mapping(address => TradeDetail)) public userData;
    // Pool => accPerShare
    mapping(address => uint256) public accPerShares;
    // Pool => totalSupply
    mapping(address => uint256) public totalHoldAmounts;


    //////////////////////////////// Errors ////////////////////////////////

    error ZeroAmount();
    error AmountExceed();
    error NotPool();
    error AlreadySet();


    /// @dev 01 00 01 00 01 01 01
    constructor(
        bytes32 flag_data
    ) BaseModule(flag_data) {

    }


    //////////////////////////////// Events ////////////////////////////////

    event GetReward(address pool, address user, uint256 amount);
    event Donate(address who, address pool, uint256 amount);
    event UpdatePerShare(address pool, uint256 amount);


    /// @notice record start time & start price
    function initialize() external {
        if (startTime[msg.sender] != 0) { revert AlreadySet(); }
        startTime[msg.sender] = block.timestamp;
    }

    //////////////////////////////// User Functions ////////////////////////////////

    /// @dev User To Collect Mining
    function collect(address pool) external {
        address _user = msg.sender;
        uint256 accPerShare = accPerShares[pool];
        TradeDetail storage data = userData[pool][_user];
        // Rewards Settlement
        uint256 holdAmount = data.holdAmount;
        _earning(pool, _user, accPerShare, holdAmount, data.rewardDebt);
        // Change Data
        data.rewardDebt = holdAmount * accPerShare / PRECISION;
    }

    function donate(address pool) external payable {
        uint256 donateAmount = msg.value;
        if (donateAmount == 0) { revert ZeroAmount(); }
        uint256 totalHoldAmount = totalHoldAmounts[pool];
        if (totalHoldAmount == 0) { revert NotPool(); }
        uint256 accPerShare = accPerShares[pool];
        accPerShare += donateAmount * PRECISION / totalHoldAmount;
        accPerShares[pool] = accPerShare;
        emit UpdatePerShare(pool, accPerShare);
        emit Donate(msg.sender, pool, donateAmount);
    }

    //////////////////////////////// Hooks ////////////////////////////////

    /// @dev Equal to Sell
    function afterAdd(
        address _user,
        uint256 _tokenIn,
        uint256 // _nativeIn
    ) external {
        address pool = msg.sender;
        uint256 accPerShare = accPerShares[pool];
        TradeDetail storage data = userData[pool][_user];
        // Rewards Settlement
        uint256 holdAmount = data.holdAmount;
        uint256 principle = data.principle;
        _earning(pool, _user, accPerShare, holdAmount, data.rewardDebt);
        // Change Data
        data.holdAmount = holdAmount - _tokenIn;
        totalHoldAmounts[pool] -= _tokenIn;
        data.principle = principle - principle * _tokenIn / holdAmount;
        data.rewardDebt = (holdAmount - _tokenIn) * accPerShare / PRECISION;
    }

    /// @dev Equal to Buy
    function afterRemove(
        address _user,
        uint256 _tokenOut,
        uint256 _nativeOut
    ) external {
        address pool = msg.sender;
        uint256 accPerShare = accPerShares[pool];
        TradeDetail storage data = userData[pool][_user];
        // Rewards Settlement
        uint256 holdAmount = data.holdAmount;
        _earning(pool, _user, accPerShare, holdAmount, data.rewardDebt);
        // Change Data
        data.holdAmount = holdAmount + _tokenOut;
        totalHoldAmounts[pool] += _tokenOut;
        data.principle = data.principle + _nativeOut;
        data.rewardDebt = (holdAmount + _tokenOut) * accPerShare / PRECISION;
    }


    function afterBuy(
        address _trader,
        uint256 _amountIn,
        uint256 _amountOut
    ) external returns (uint256) {
        address pool = msg.sender;
        uint256 accPerShare = accPerShares[pool];
        TradeDetail storage data = userData[pool][_trader];
        // Rewards Settlement
        uint256 holdAmount = data.holdAmount;
        _earning(pool, _trader, accPerShare, holdAmount, data.rewardDebt);
        // New Status Record
        data.holdAmount = holdAmount + _amountOut;
        totalHoldAmounts[pool] += _amountOut;
        data.principle += _amountIn;
        data.rewardDebt = (holdAmount + _amountOut) * accPerShare / PRECISION;
        return _amountOut;
    }


    function afterSell(
        address _trader,
        uint256 _amountIn,
        uint256 _amountOut
    ) external returns (uint256 amountOut) {
        address pool = msg.sender;
        uint256 accPerShare = accPerShares[pool];
        TradeDetail storage data = userData[pool][_trader];
        // Rewards Settlement
        uint256 holdAmount = data.holdAmount;
        _earning(pool, _trader, accPerShare, holdAmount, data.rewardDebt);
        uint256 principle;
        uint256 profit;
        (amountOut, principle, profit) = _quoteSell(pool, _trader, _amountIn, _amountOut);
        uint256 totalHoldAmount = totalHoldAmounts[pool];

        // Update UserData
        data.holdAmount = holdAmount - _amountIn;
        totalHoldAmounts[pool] -= _amountIn;
        data.principle -= principle;
        data.rewardDebt = (holdAmount - _amountIn) * accPerShare / PRECISION;

        // Update accPerShare
        if (profit > 0) {
            if (totalHoldAmount != _amountIn) {
                accPerShares[pool] = accPerShare + profit * PRECISION / (totalHoldAmount - _amountIn);
            } else {
                amountOut = amountOut + profit;
            }
        }

    }


    //////////////////////////////// VIEW FUNCTIONS ////////////////////////////////

    function quoteBuy(
        address , // _trader,
        uint256 , // _amountIn,
        uint256 _amountOut
    ) external pure returns (uint256) {
        return _amountOut;
    }

    /// @dev If the Last TokenHolder Sell All the Tokens to the Pool, This Function Can not Work
    function quoteSell(
        address _trader,
        uint256 _amountIn,
        uint256 _amountOut
    ) external view returns (uint256 amountOut) {
        (amountOut, ,) = _quoteSell(msg.sender, _trader, _amountIn, _amountOut);
    }

    function claimableAmount(address pool, address user) external view returns (uint256 pending) {
        uint256 accPerShare = accPerShares[pool];
        TradeDetail memory data = userData[pool][user];
        // Rewards Settlement
        uint256 holdAmount = data.holdAmount;
        if (holdAmount > 0) {
            pending = holdAmount * accPerShare / PRECISION - data.rewardDebt;
        }
    }

    //////////////////////////////// INTERNAL FUNCTIONS ////////////////////////////////

    function _quoteSell(
        address _pool,
        address _trader,
        uint256 _amountIn,
        uint256 _amountOut
    ) internal view returns (uint256 amountOut, uint256 principle, uint256 profit) {
        amountOut = _amountOut;
        TradeDetail memory data = userData[_pool][_trader];
        if (_amountIn == data.holdAmount) {
            principle = data.principle;
        } else {
            principle = _amountIn * data.principle / data.holdAmount;
        }
        uint256 maxOut = principle + principle * (uint256(block.timestamp) - startTime[_pool]) / GROWTH_COEFFICIENT;
        if (_amountOut > maxOut) {
            profit = _amountOut - maxOut;
            amountOut = maxOut;
        }
    }

    function _earning(
        address _pool,
        address _user,
        uint256 _accPerShare,
        uint256 _holdAmount,
        uint256 _rewardDebt
    ) internal {
        if (_holdAmount > 0) {
            uint256 pending = _holdAmount * _accPerShare / PRECISION - _rewardDebt;
            if (pending > 0) {
                payable(_user).transfer(pending);
                emit GetReward(_pool, _user, pending);
            }
        }
    }

    receive() external payable {}

}
