// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;
import "../../SYBase.sol";
import "../../../libraries/ArrayLib.sol";
import "../../../../interfaces/Stader/IStaderStakeManager.sol";

contract PendleETHXSY is SYBase {
    using PMath for uint256;

    error StaderMaxDepositExceed(uint256 amountToDeposit, uint256 maxDeposit);
    error StaderMinDepositUnreached(uint256 amountToDeposit, uint256 minDeposit);

    address public immutable stakeManager;
    address public immutable ethx;

    constructor(address _stakeManager, address _ethx) SYBase("SY Stader Staking ETHx", "SY-ETHx", _ethx) {
        stakeManager = _stakeManager;
        ethx = _ethx;
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    function _deposit(
        address tokenIn,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == NATIVE) {
            return IStaderStakeManager(stakeManager).deposit{value: amountDeposited}(address(this));
        } else {
            return amountDeposited;
        }
    }

    function _redeem(
        address receiver,
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal virtual override returns (uint256 /*amountTokenOut*/) {
        _transferOut(ethx, receiver, amountSharesToRedeem);
        return amountSharesToRedeem;
    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    function exchangeRate() public view virtual override returns (uint256) {
        return IStaderStakeManager(stakeManager).getExchangeRate();
    }

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == NATIVE) {
            uint256 maxDeposit = IStaderStakeManager(stakeManager).maxDeposit();
            uint256 minDeposit = IStaderStakeManager(stakeManager).minDeposit();
            if (amountTokenToDeposit > maxDeposit) {
                revert StaderMaxDepositExceed(amountTokenToDeposit, maxDeposit);
            }
            if (amountTokenToDeposit < minDeposit) {
                revert StaderMinDepositUnreached(amountTokenToDeposit, minDeposit);
            }
            return IStaderStakeManager(stakeManager).previewDeposit(amountTokenToDeposit);
        } else {
            return amountTokenToDeposit;
        }
    }

    function _previewRedeem(
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal pure override returns (uint256 /*amountTokenOut*/) {
        return amountSharesToRedeem;
    }

    function getTokensIn() public view virtual override returns (address[] memory) {
        return ArrayLib.create(NATIVE, ethx);
    }

    function getTokensOut() public view virtual override returns (address[] memory) {
        return ArrayLib.create(ethx);
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == ethx || token == NATIVE;
    }

    function isValidTokenOut(address token) public view virtual override returns (bool) {
        return token == ethx;
    }

    function assetInfo() external pure returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, NATIVE, 18);
    }
}
