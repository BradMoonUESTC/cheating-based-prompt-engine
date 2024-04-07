// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../../SYBaseWithRewards.sol";
import "../../../libraries/ArrayLib.sol";
import "../../../../interfaces/HMX/IHMXCompounder.sol";
import "../../../../interfaces/HMX/IHLPStaking.sol";
import "../../../../interfaces/HMX/IHMXStaking.sol";
import "../../../../interfaces/HMX/IHMXVester.sol";
import "./HLPPricingHelper.sol";

contract PendleHlpSY is SYBaseWithRewards {
    using ArrayLib for address[];

    address public immutable hlp;
    address public immutable usdc;
    address public immutable compounder;

    address public immutable vester;
    address public immutable hlpStakingPool;
    address public immutable hmxStakingPool;

    address[] public allRewardTokens;

    // off-chain usage only, no security related, no auditing required
    address public immutable hlpPriceHelper;

    constructor(
        string memory _name,
        string memory _symbol,
        address _hlp,
        address _usdc,
        address _compounder,
        address _vester,
        address _hlpStakingPool,
        address _hmxStakingPool,
        address _hlpPriceHelper
    ) SYBaseWithRewards(_name, _symbol, _hlp) {
        hlp = _hlp;
        usdc = _usdc;

        compounder = _compounder;
        vester = _vester;

        hlpStakingPool = _hlpStakingPool;
        hmxStakingPool = _hmxStakingPool;

        hlpPriceHelper = _hlpPriceHelper;

        allRewardTokens.push(_usdc);
        _safeApproveInf(hlp, hlpStakingPool);
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev See {SYBase-_deposit}
     */
    function _deposit(
        address,
        /*tokenIn*/ uint256 amountDeposited
    ) internal virtual override returns (uint256 /*amountSharesOut*/) {
        IHLPStaking(hlpStakingPool).deposit(address(this), amountDeposited);
        return amountDeposited;
    }

    /**
     * @dev See {SYBase-_redeem}
     */
    function _redeem(
        address receiver,
        address,
        /*tokenOut*/ uint256 amountSharesToRedeem
    ) internal virtual override returns (uint256 /*amountTokenOut*/) {
        IHLPStaking(hlpStakingPool).withdraw(amountSharesToRedeem);
        _transferOut(hlp, receiver, amountSharesToRedeem);
        return amountSharesToRedeem;
    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    function exchangeRate() public view virtual override returns (uint256) {
        return PMath.ONE;
    }

    /*///////////////////////////////////////////////////////////////
                               REWARDS-RELATED
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev See {IStandardizedYield-getRewardTokens}
     */

    function addRewardToken(address token) external onlyOwner {
        require(!allRewardTokens.contains(token), "invalid additional reward token");
        allRewardTokens.push(token);
    }

    function _getRewardTokens() internal view override returns (address[] memory res) {
        return allRewardTokens;
    }

    function _redeemExternalReward() internal override {
        address[] memory pools = new address[](2);
        pools[0] = hmxStakingPool;
        pools[1] = hlpStakingPool;

        address[][] memory rewarders = new address[][](2);

        rewarders[0] = IHMXStaking(hmxStakingPool).getAllRewarders();
        rewarders[1] = IHLPStaking(hlpStakingPool).getRewarders(); // Surge HLP programme is redundent but it's not very gas-sensitive

        IHMXCompounder(compounder).compound(pools, rewarders, 0, 0, new uint256[](0));
    }

    /*///////////////////////////////////////////////////////////////
                    MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address,
        /*tokenIn*/ uint256 amountTokenToDeposit
    ) internal pure override returns (uint256 /*amountSharesOut*/) {
        return amountTokenToDeposit;
    }

    function _previewRedeem(
        address,
        /*tokenOut*/ uint256 amountSharesToRedeem
    ) internal pure override returns (uint256 /*amountTokenOut*/) {
        return amountSharesToRedeem;
    }

    function getTokensIn() public view virtual override returns (address[] memory res) {
        res = new address[](1);
        res[0] = hlp;
    }

    function getTokensOut() public view virtual override returns (address[] memory res) {
        res = new address[](1);
        res[0] = hlp;
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == hlp;
    }

    function isValidTokenOut(address token) public view virtual override returns (bool) {
        return token == hlp;
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.LIQUIDITY, hlp, IERC20Metadata(hlp).decimals());
    }

    /*///////////////////////////////////////////////////////////////
                        esHMX vest & claim
    //////////////////////////////////////////////////////////////*/

    function vestAllEsHMX(address to) external onlyOwner {
        _updateAndDistributeRewards(to); // to correctly trigger _redeemExternalReward
        address esHMX = IHMXVester(vester).esHMX();
        uint256 amountToVest = IHMXStaking(hmxStakingPool).userTokenAmount(esHMX, address(this));
        IHMXStaking(hmxStakingPool).withdraw(esHMX, amountToVest);

        _safeApproveInf(esHMX, vester);
        IHMXVester(vester).vestFor(to, amountToVest, 365 days);
    }

    /*///////////////////////////////////////////////////////////////
                        OFF-CHAIN USAGE ONLY
            (NO SECURITY RELATED && CAN BE LEFT UNAUDITED)
    //////////////////////////////////////////////////////////////*/

    function getPrice() external view returns (uint256) {
        return HLPPricingHelper(hlpPriceHelper).getPrice();
    }
}
