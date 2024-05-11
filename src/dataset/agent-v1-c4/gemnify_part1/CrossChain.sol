// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {ICrossChain} from "./interfaces/ICrossChain.sol";
import {INftPool} from "./interfaces/INftPool.sol";
import {IRewardRouterV2} from "../staking/interfaces/IRewardRouterV2.sol";

import {IStargateRouter} from "./interfaces/IStargateRouter.sol";
import {IStargateRouterETH} from "./interfaces/IStargateRouterETH.sol";
import {NonblockingLzApp} from "./layerZero/NonblockingLzApp.sol";
import {Constants} from "./libraries/helpers/Constants.sol";

contract CrossChain is ICrossChain, NonblockingLzApp {
    INftPool public nftPool;
    IRewardRouterV2 public rewardRouter;
    address public refinance;

    uint16 public dstChainId;
    IStargateRouter public stargateRouter;
    IStargateRouterETH public stargateRouterETH;
    uint16 public srcPoolId;
    uint16 public dstPoolId;

    uint16 public constant VERSION = 1;
    uint256 public gasForDestinationLzReceive;
    uint256 public minSwapAmountPct = 9900;
    uint256 public gasIncrementPct = 20000;
    uint256 public crossChainFee;

    modifier onlyNftPool() {
        require(msg.sender == address(nftPool), "cc: forbidden");
        _;
    }

    modifier onlyRewardRouter() {
        require(msg.sender == address(rewardRouter), "cc: forbidden");
        _;
    }

    modifier onlyRefinance() {
        require(msg.sender == refinance, "cc: forbidden");
        _;
    }

    constructor(address _endpoint) NonblockingLzApp(_endpoint) {}

    function setNftPool(address _addr) external onlyOwner {
        require(_addr != address(0), "cc: nftPool can't be null");
        nftPool = INftPool(_addr);
    }

    function setGasForDestinationLzReceive(uint256 _gas) external onlyOwner {
        require(_gas != 0, "cc: gas can't be 0");
        gasForDestinationLzReceive = _gas;
    }

    function setRewardRouter(address _addr) external onlyOwner {
        require(_addr != address(0), "cc: rewardRouter can't be null");
        rewardRouter = IRewardRouterV2(_addr);
    }

    function setRefinance(address _addr) external onlyOwner {
        require(_addr != address(0), "cc: refinance can't be null");
        refinance = _addr;
    }

    function setMinSwapAmountPct(uint256 _amount) external onlyOwner {
        require(
            _amount <= Constants.PERCENTAGE_FACTOR,
            "cc: swap amount pct not invalid"
        );
        minSwapAmountPct = _amount;
    }

    function setGasIncrementPct(uint256 _amount) external onlyOwner {
        gasIncrementPct = _amount;
    }

    function setDstChainId(uint16 _dstChainId) external onlyOwner {
        dstChainId = _dstChainId;
    }

    function setCrossChainFee(uint256 _fee) external onlyOwner {
        crossChainFee = _fee;
    }

    function setStargateParameters(
        uint16 _srcPoolId,
        uint16 _dstPoolId,
        address _stargateRouter,
        address _stargateRouterETH
    ) external onlyOwner {
        require(
            _stargateRouter != address(0),
            "cc: stargateRouter can't be null"
        );
        stargateRouter = IStargateRouter(_stargateRouter);
        stargateRouterETH = IStargateRouterETH(_stargateRouterETH);
        srcPoolId = _srcPoolId;
        dstPoolId = _dstPoolId;
    }

    function _nonblockingLzReceive(
        uint16 /*_srcChainId*/,
        bytes memory /*_srcAddress*/,
        uint64 /*_nonce*/,
        bytes memory _payload
    ) internal override {
        uint8 functionType;
        assembly {
            functionType := mload(add(_payload, 32))
        }
        if (functionType == uint8(FunctionType.DEPOSIT)) {
            (
                ,
                address user,
                address[] memory nfts,
                uint256[][] memory tokenIds
            ) = abi.decode(_payload, (uint8, address, address[], uint256[][]));

            address _nft;
            uint256 _tokenId;
            for (uint256 i = 0; i < nfts.length; i++) {
                _nft = nfts[i];
                require(tokenIds[i].length > 0, "cc: empty tokenIds");
                for (uint256 j = 0; j < tokenIds[i].length; j++) {
                    _tokenId = tokenIds[i][j];
                    rewardRouter.mintAndStakeUlpNFT(user, _nft, _tokenId, 0, 0);
                }
            }
        } else if (functionType == uint8(FunctionType.WITHDRAW)) {
            (
                ,
                address user,
                address[] memory nfts,
                uint256[][] memory tokenIds
            ) = abi.decode(_payload, (uint8, address, address[], uint256[][]));
            nftPool.withdraw(user, nfts, tokenIds);
        } else if (functionType == uint8(FunctionType.REFINANCE)) {
            (
                ,
                address[] memory users,
                address[] memory nfts,
                uint256[] memory tokenIds
            ) = abi.decode(_payload, (uint8, address[], address[], uint256[]));
            nftPool.refinance(users, nfts, tokenIds);
        }
    }

    function sendDepositNftMsg(
        address payable _user,
        address[] calldata _nfts,
        uint256[][] calldata _tokenIds
    ) external payable override onlyNftPool {
        bytes memory payload = abi.encode(
            FunctionType.DEPOSIT,
            _user,
            _nfts,
            _tokenIds
        );
        bytes memory adapterParams = abi.encodePacked(
            VERSION,
            gasForDestinationLzReceive
        );
        _lzSend(
            dstChainId,
            payload,
            _user,
            address(0x00),
            adapterParams,
            msg.value
        );
    }

    function sendWithDrawNftMsg(
        address payable _user,
        address[] calldata _nfts,
        uint256[][] calldata _tokenIds
    ) external payable override onlyRewardRouter {
        bytes memory payload = abi.encode(
            FunctionType.WITHDRAW,
            _user,
            _nfts,
            _tokenIds
        );
        bytes memory adapterParams = abi.encodePacked(
            VERSION,
            gasForDestinationLzReceive
        );

        _lzSend(
            dstChainId,
            payload,
            _user,
            address(0x00),
            adapterParams,
            msg.value
        );
    }

    function sendRefinanceNftMsg(
        address[] calldata _users,
        address[] calldata _nfts,
        uint256[] calldata _tokenIds,
        address payable _refundAddress
    ) external payable override onlyRefinance {
        bytes memory payload = abi.encode(
            FunctionType.REFINANCE,
            _users,
            _nfts,
            _tokenIds
        );
        bytes memory adapterParams = abi.encodePacked(
            VERSION,
            gasForDestinationLzReceive
        );

        _lzSend(
            dstChainId,
            payload,
            _refundAddress,
            address(0x00),
            adapterParams,
            msg.value
        );
    }

    function swapETH(
        address payable _refundAddress,
        address _toAddress,
        uint256 _swapValue
    ) external payable override onlyNftPool {
        require(msg.value > _swapValue, "cc: msg value is not enough");
        stargateRouterETH.swapETH{value: msg.value}(
            dstChainId,
            _refundAddress,
            abi.encodePacked(_toAddress),
            _swapValue,
            (_swapValue * minSwapAmountPct) / Constants.PERCENTAGE_FACTOR
        );
    }

    function estimateSwapFee(
        address toAddress
    ) external view returns (uint256) {
        (uint256 feeWei, ) = stargateRouter.quoteLayerZeroFee(
            dstChainId,
            1,
            abi.encode(toAddress),
            "0x",
            IStargateRouter.lzTxObj(0, 0, "0x")
        );
        return feeWei + (feeWei * gasIncrementPct / Constants.PERCENTAGE_FACTOR);
    }

    function estimateDepositFee(
        address _user,
        address[] calldata _nfts,
        uint256[][] calldata _tokenIds
    ) external view returns (uint256) {
        bytes memory payload = abi.encode(
            FunctionType.DEPOSIT,
            _user,
            _nfts,
            _tokenIds
        );
        return estimateLayerZeroFee(payload);
    }

    function estimateWithdrawFee(
        address _user,
        address[] calldata _nfts,
        uint256[][] calldata _tokenIds
    ) external view returns (uint256) {
        bytes memory payload = abi.encode(
            FunctionType.WITHDRAW,
            _user,
            _nfts,
            _tokenIds
        );
        return estimateLayerZeroFee(payload);
    }

    function estimateRefinanceFee(
        address[] calldata _users,
        address[] calldata _nfts,
        uint256[] calldata _tokenIds
    ) external view returns (uint256) {
        bytes memory payload = abi.encode(
            FunctionType.REFINANCE,
            _users,
            _nfts,
            _tokenIds
        );
        return estimateLayerZeroFee(payload);
    }

    function estimateLayerZeroFee(
        bytes memory payload
    ) public view returns (uint256) {
        bytes memory adapterParams = abi.encodePacked(
            VERSION,
            gasForDestinationLzReceive
        );
        (uint256 estimateFee, ) = lzEndpoint.estimateFees(
            dstChainId,
            msg.sender,
            payload,
            false,
            adapterParams
        );

        return
            estimateFee > crossChainFee ?
            estimateFee + (estimateFee * gasIncrementPct / Constants.PERCENTAGE_FACTOR):
            crossChainFee;
    }
}
