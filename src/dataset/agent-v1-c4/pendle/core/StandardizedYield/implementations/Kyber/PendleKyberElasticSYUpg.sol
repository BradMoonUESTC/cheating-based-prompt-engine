// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./KyberNftManagerBaseUpg.sol";
import "../../SYBaseWithRewardsUpg.sol";

contract PendleKyberElasticSYUpg is SYBaseWithRewardsUpg, KyberNftManagerBaseUpg {
    using ArrayLib for address[];

    event DepositNft(address indexed user, uint256 indexed tokenId, uint256 amountSharesOut);

    event WithdrawNft(address indexed user, uint256 indexed tokenId, uint256 amountSharesToWithdraw);

    address[] internal allRewardTokens;

    constructor(
        KyberNftManagerImmutableParams memory params
    ) KyberNftManagerBaseUpg(params) SYBaseUpg(params.pool) initializer {}

    function initialize(
        string memory _name,
        string memory _symbol,
        address[] memory _initialRewardTokens
    ) external initializer {
        allRewardTokens = _initialRewardTokens;
        __SYBaseUpg_init(_name, _symbol);
        __KyberNftManagerBaseUpg_init();
    }

    function depositNft(uint256 tokenId) external returns (uint256 amountSharesOut) {
        amountSharesOut = _depositNft(tokenId);
        _mint(msg.sender, amountSharesOut);
        emit DepositNft(msg.sender, tokenId, amountSharesOut);
    }

    function withdrawNft(uint256 amountSharesToWithdraw) external returns (uint256 tokenId) {
        _burn(msg.sender, amountSharesToWithdraw);
        tokenId = _withdrawNft(amountSharesToWithdraw, msg.sender);
        emit WithdrawNft(msg.sender, tokenId, amountSharesToWithdraw);
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    function _deposit(
        address tokenIn,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 amountSharesOut) {
        return _zapIn(tokenIn, amountDeposited);
    }

    function _redeem(
        address receiver,
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal virtual override returns (uint256 amountTokenOut) {
        amountTokenOut = _zapOut(tokenOut, amountSharesToRedeem);
        _transferOut(tokenOut, receiver, amountTokenOut);
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

    function addRewardToken(address rewardToken) external onlyOwner {
        require(!allRewardTokens.contains(rewardToken), "rewardToken already existed");
        allRewardTokens.push(rewardToken);
    }

    /**
     * @dev See {IStandardizedYield-getRewardTokens}
     */
    function _getRewardTokens() internal view override returns (address[] memory res) {
        return allRewardTokens;
    }

    function _redeemExternalReward() internal override {
        _claimKyberRewards();
    }

    /*///////////////////////////////////////////////////////////////
                        MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view override returns (uint256 amountSharesOut) {
        return
            IKyberMathHelper(kyberMathHelper).previewDeposit(
                pool,
                tickLower,
                tickUpper,
                tokenIn == token0,
                amountTokenToDeposit
            );
    }

    function _previewRedeem(
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal view override returns (uint256 amountTokenOut) {
        return
            IKyberMathHelper(kyberMathHelper).previewRedeem(
                pool,
                tickLower,
                tickUpper,
                tokenOut == token0,
                amountSharesToRedeem
            );
    }

    function getTokensIn() public view virtual override returns (address[] memory res) {
        res = new address[](2);
        res[0] = token0;
        res[1] = token1;
    }

    function getTokensOut() public view virtual override returns (address[] memory res) {
        res = new address[](2);
        res[0] = token0;
        res[1] = token1;
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == token0 || token == token1;
    }

    function isValidTokenOut(address token) public view virtual override returns (bool) {
        return token == token0 || token == token1;
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, pool, 18);
    }

    /*///////////////////////////////////////////////////////////////
                       POC for Emergency functions
    //////////////////////////////////////////////////////////////*/

    // function toggleEmergencyStatus() external {
    //     // This function only acts as a POC. Any other call to this SY should also execute the withdraw emergency
    //     require(IKyberLiquidityMining(liquidityMining).emergencyEnabled(), "not emergency");
    //     _withdrawNftFromFarm(KyberLiquidityMiningStatus.EMERGENCY);
    // }
}
