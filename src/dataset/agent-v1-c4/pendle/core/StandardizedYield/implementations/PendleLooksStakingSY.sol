// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../SYBase.sol";
import "../../../interfaces/ILooksFeeSharing.sol";
import "../../../interfaces/ILooksStaking.sol";

contract PendleLooksStakingSY is SYBase {
    using PMath for uint256;

    address public immutable looks;
    address public immutable stakingContract;
    address public immutable feeSharingContract;

    constructor(
        string memory _name,
        string memory _symbol,
        address _looks,
        address _stakingContract,
        address _feeSharingContract
    ) SYBase(_name, _symbol, _looks) {
        looks = _looks;
        stakingContract = _stakingContract;
        feeSharingContract = _feeSharingContract;

        _safeApproveInf(_looks, _stakingContract);
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    function _deposit(address, uint256 amountDeposited) internal virtual override returns (uint256 amountSharesOut) {
        uint256 previousShare = ILooksStaking(stakingContract).userInfo(address(this));
        ILooksStaking(stakingContract).deposit(amountDeposited);
        amountSharesOut = ILooksStaking(stakingContract).userInfo(address(this)) - previousShare;
    }

    function _redeem(
        address receiver,
        address,
        uint256 amountSharesToRedeem
    ) internal virtual override returns (uint256 amountTokenOut) {
        uint256 previousBalance = _selfBalance(looks);
        ILooksStaking(stakingContract).withdraw(amountSharesToRedeem);
        amountTokenOut = _selfBalance(looks) - previousBalance;
        _transferOut(looks, receiver, amountTokenOut);
    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    function exchangeRate() public view virtual override returns (uint256) {
        (uint256 totalShares, uint256 totalLooks) = _getLooksStakingParams();
        return totalLooks.divDown(totalShares);
    }

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address,
        uint256 amountTokenToDeposit
    ) internal view override returns (uint256 amountSharesOut) {
        (uint256 totalShares, uint256 totalLooks) = _getLooksStakingParams();
        amountSharesOut = (amountTokenToDeposit * totalShares) / totalLooks;
    }

    function _previewRedeem(
        address,
        uint256 amountSharesToRedeem
    ) internal view override returns (uint256 amountTokenOut) {
        (uint256 totalShares, uint256 totalLooks) = _getLooksStakingParams();
        amountTokenOut = (amountSharesToRedeem * totalLooks) / totalShares;
    }

    function _getLooksStakingParams() private view returns (uint256 totalShares, uint256 totalLooks) {
        totalShares = ILooksStaking(stakingContract).totalShares();
        totalLooks = ILooksFeeSharing(feeSharingContract).calculateSharesValueInLOOKS(stakingContract);
    }

    function getTokensIn() public view virtual override returns (address[] memory res) {
        res = new address[](1);
        res[0] = looks;
    }

    function getTokensOut() public view virtual override returns (address[] memory res) {
        res = new address[](1);
        res[0] = looks;
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == looks;
    }

    function isValidTokenOut(address token) public view virtual override returns (bool) {
        return token == looks;
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, looks, IERC20Metadata(looks).decimals());
    }
}
