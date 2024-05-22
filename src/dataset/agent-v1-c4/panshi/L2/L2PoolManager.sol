// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import "../../interfaces/IScrollBridge.sol";
import "../../interfaces/IPolygonZkEVMBridge.sol";
import "../../interfaces/IArbitrumOneBridge.sol";
import "../../interfaces/IArbitrumNovaBridge.sol";
import "../../interfaces/IOptimismBridge.sol";
import "../../interfaces/IZksyncBridge.sol";
import "../../interfaces/IMantleBridge.sol";
import "../../interfaces/IMantaBridge.sol";
import "../../interfaces/WETH.sol";
import "../../interfaces/IL2PoolManager.sol";
import "../libraries/ContractsAddress.sol";
import "../bridge/TokenBridgeBase.sol";
import "../../interfaces/IMessageManager.sol";

contract L2PoolManager is IL2PoolManager, PausableUpgradeable, TokenBridgeBase {
    uint32 public MAX_GAS_Limit;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _MultisigWallet,
        address _messageManager
    ) public initializer {
        __AccessControl_init();
        __Pausable_init();
        TokenBridgeBase.__TokenBridge_init(_MultisigWallet, _messageManager);
        MAX_GAS_Limit = 300000;
    }

    /* admin functions */
    function WithdrawETHtoL1(
        address _to,
        uint256 _amount
    ) external payable onlyRole(ReLayer) returns (bool) {
        uint256 Blockchain = block.chainid;
        if (_amount > address(this).balance) {
            revert NotEnoughETH();
        }
        if (Blockchain == 0x82750) {
            //Scroll https://chainlist.org/chain/534352
            IScrollStandardL2ETHBridge(
                ContractsAddress.ScrollL2StandardETHBridge
            ).withdrawETH{gas: MAX_GAS_Limit, value: _amount}(
                _to,
                _amount,
                uint256(MAX_GAS_Limit)
            );
        } else if (Blockchain == 0x44d) {
            // Polygon zkEVM https://chainlist.org/chain/1101
            IPolygonZkEVML2Bridge(ContractsAddress.PolygonZkEVML2Bridge)
                .bridgeAsset{value: _amount}(
                0,
                _to,
                _amount,
                address(0),
                false,
                ""
            );
        } else if (Blockchain == 0xa) {
            //OP Mainnet https://chainlist.org/chain/10
            IOptimismL2StandardBridge(ContractsAddress.OptimismL2StandardBridge)
                .withdrawTo{value: _amount}(
                ContractsAddress.OP_LEGACY_ERC20_ETH,
                _to,
                _amount,
                MAX_GAS_Limit,
                ""
            );
        } else if (Blockchain == 0xa4b1) {
            // Arbitrum One https://chainlist.org/chain/42161
            IArbitrumOneL2Bridge(ContractsAddress.ArbitrumOneL2GatewayRouter)
                .outboundTransfer{value: _amount}(
                ContractsAddress.ETHAddress,
                _to,
                _amount,
                ""
            );
        } else if (Blockchain == 0xa4ba) {
            // Arbitrum One https://chainlist.org/chain/42170
            IArbitrumNovaL2Bridge(ContractsAddress.ArbitrumNovaL2GatewayRouter)
                .outboundTransfer{value: _amount}(
                ContractsAddress.ETHAddress,
                _to,
                _amount,
                ""
            );
        }  else if (Blockchain == 0x144) {
            //https://chainlist.org/chain/324
            //ZkSync Mainnet
            //https://github.com/zksync-sdk/zksync-ethers/blob/main/src/utils.ts#L92
            IZkSyncBridge(ContractsAddress.ZkSyncL2Bridge).withdraw{value: _amount}(
                _to,
                address(0),
                _amount
            );
        }  else if (Blockchain == 0x1388) {
            //https://chainlist.org/chain/324
            //Mantle Mainnet
            IERC20(ContractsAddress.MantleETH).approve(
                ContractsAddress.MantleL2Bridge,
                _amount
            );
            IMantleL2Bridge(ContractsAddress.MantleL2Bridge).withdrawto(
                ContractsAddress.MantleETH,
                _to,
                _amount,
                MAX_GAS_Limit,
                ""
            );

        } else if (Blockchain == 0xa9) {
            //Manta Pacific Mainnet https://chainlist.org/chain/169
            IMantaL2Bridge(ContractsAddress.MantaL2Bridge)
                .withdrawTo{value: _amount}(
                ContractsAddress.OP_LEGACY_ERC20_ETH,
                _to,
                _amount,
                MAX_GAS_Limit,
                ""
            );
        } else if (Blockchain == 0xa70e) {
            // ZKFair https://chainlist.org/chain/42766
            // ETH in ZKFair is ERC20
            IERC20(ContractsAddress.ZKFairETH).approve(
                ContractsAddress.ZKFairL2Bridge,
                _amount
            );
            IPolygonZkEVML2Bridge(ContractsAddress.ZKFairL2Bridge)
                .bridgeAsset(0, _to, _amount, ContractsAddress.ZKFairETH, false, "");
        } else if (Blockchain == 0x2105) {
            //Base 
            IOptimismL2StandardBridge(ContractsAddress.BaseL2StandardBridge)
                .withdrawTo{value: _amount}(
                ContractsAddress.BASE_LEGACY_ERC20_ETH,
                _to,
                _amount,
                MAX_GAS_Limit,
                ""
            );
        }
        else {
            revert ErrorBlockChain();
        }
        FundingPoolBalance[ContractsAddress.ETHAddress] -= _amount;
        emit WithdrawETHtoL1Success(
            block.chainid,
            block.timestamp,
            _to,
            _amount
        );
        return true;
    }

    function WithdrawWETHToL1(
        address _to,
        uint256 _amount
    ) external payable onlyRole(ReLayer) returns (bool) {
        uint256 Blockchain = block.chainid;
        IWETH WETH = IWETH(L2WETH());
        if (_amount > WETH.balanceOf(address(this))) {
            revert NotEnoughToken(address(WETH));
        }
        if (Blockchain == 0x82750) {
            // Scroll https://chainlist.org/chain/534352
            WETH.approve(ContractsAddress.ScrollL2StandardWETHBridge, _amount);
            IScrollStandardL2WETHBridge(
                ContractsAddress.ScrollL2StandardWETHBridge
            ).withdrawERC20{gas: MAX_GAS_Limit}(
                address(WETH),
                _to,
                _amount,
                uint256(MAX_GAS_Limit)
            );
        } else if (Blockchain == 0x44d) {
            // Polygon zkEVM https://chainlist.org/chain/1101
            WETH.approve(ContractsAddress.PolygonZkEVML2Bridge, _amount);
            IPolygonZkEVML2Bridge(ContractsAddress.PolygonZkEVML2Bridge)
                .bridgeAsset{value: _amount}(
                0,
                _to,
                _amount,
                address(0),
                false,
                ""
            );
        } else if (Blockchain == 0xa) {
            // OP Mainnet https://chainlist.org/chain/10
            WETH.approve(ContractsAddress.OptimismL2StandardBridge, _amount);
            IOptimismL2StandardBridge(ContractsAddress.OptimismL2StandardBridge)
                .withdrawTo{value: _amount}(
                address(WETH),
                _to,
                _amount,
                MAX_GAS_Limit,
                ""
            );
        } else if (Blockchain == 0x2105) {
            // Base https://chainlist.org/chain/2105
            WETH.approve(ContractsAddress.BaseL2StandardBridge, _amount);
            IOptimismL2StandardBridge(ContractsAddress.BaseL2StandardBridge)
                .withdrawTo{value: _amount}(
                address(WETH),
                _to,
                _amount,
                MAX_GAS_Limit,
                ""
            );
        } 
        else if (Blockchain == 0xa4b1) {
            // Arbitrum One https://chainlist.org/chain/42161
            WETH.approve(ContractsAddress.ArbitrumOneL2WETHGateway, _amount);
            IArbitrumOneL2Bridge(ContractsAddress.ArbitrumOneL2WETHGateway)
                .outboundTransfer(ContractsAddress.WETH, _to, _amount, "");
        } else if (Blockchain == 0xa4ba) {
            // Arbitrum Nova https://chainlist.org/chain/42170
            WETH.approve(ContractsAddress.ArbitrumNovaL2WETHGateway, _amount);
            IArbitrumNovaL2Bridge(ContractsAddress.ArbitrumNovaL2WETHGateway)
                .outboundTransfer(ContractsAddress.WETH, _to, _amount, "");
        } else if(Blockchain == 0x144){
            //ZkSync Mainnet
            IZkSyncBridge(ContractsAddress.ZkSyncL2Bridge).withdraw{value: _amount}(
                _to,
                address(WETH),
                _amount
            );
        }
        
        
        else {
            revert ErrorBlockChain();
        }
        emit WithdrawWETHtoL1Success(
            block.chainid,
            block.timestamp,
            _to,
            _amount
        );
        FundingPoolBalance[ContractsAddress.WETH] -= _amount;
        return true;
    }

    function WithdrawERC20ToL1(
        address _token,
        address _to,
        uint256 _amount
    ) external payable onlyRole(ReLayer) returns (bool) {
        uint256 Blockchain = block.chainid;
        if (!IsSupportToken[_token]) {
            revert TokenIsNotSupported(_token);
        }
        if (Blockchain == 0x82750) {
            //Scroll https://chainlist.org/chain/534352
            IERC20(_token).approve(
                ContractsAddress.ScrollL1StandardERC20Bridge,
                _amount
            );
            IScrollStandardL2ERC20Bridge(
                ContractsAddress.ScrollL1StandardERC20Bridge
            ).withdrawERC20{gas: MAX_GAS_Limit}(
                _token,
                _to,
                _amount,
                uint256(MAX_GAS_Limit)
            );
        } else if (Blockchain == 0x44d) {
            // Polygon zkEVM https://chainlist.org/chain/1101
            IERC20(_token).approve(
                ContractsAddress.PolygonZkEVML2Bridge,
                _amount
            );
            IPolygonZkEVML2Bridge(ContractsAddress.PolygonZkEVML2Bridge)
                .bridgeAsset(0, _to, _amount, _token, false, "");
        } else if (Blockchain == 0xa) {
            //OP Mainnet https://chainlist.org/chain/10
            IERC20(_token).approve(
                ContractsAddress.OptimismL2StandardBridge,
                _amount
            );
            IOptimismL2StandardBridge(ContractsAddress.OptimismL2StandardBridge)
                .withdrawTo{value: _amount}(
                _token,
                _to,
                _amount,
                MAX_GAS_Limit,
                ""
            );
        } else if (Blockchain == 0x2105) {
            //Base
            IERC20(_token).approve(
                ContractsAddress.BaseL2StandardBridge,
                _amount
            );
            IOptimismL2StandardBridge(ContractsAddress.BaseL2StandardBridge)
                .withdrawTo{value: _amount}(
                _token,
                _to,
                _amount,
                MAX_GAS_Limit,
                ""
            );
        } 
        else if (Blockchain == 0xa4b1) {
            // Arbitrum One https://chainlist.org/chain/42161
            IERC20(_token).approve(
                ContractsAddress.ArbitrumOneL2ERC20Gateway,
                _amount
            );
            IArbitrumOneL2Bridge(ContractsAddress.ArbitrumOneL2ERC20Gateway)
                .outboundTransfer(_token, _to, _amount, "");
        } else if (Blockchain == 0xa4ba) {
            // Arbitrum Nova https://chainlist.org/chain/421611
            IERC20(_token).approve(
                ContractsAddress.ArbitrumNovaL1ERC20Gateway,
                _amount
            );
            IArbitrumNovaL2Bridge(ContractsAddress.ArbitrumNovaL1ERC20Gateway)
                .outboundTransfer(_token, _to, _amount, "");
        } else if (Blockchain == 0x144) {
            //ZkSync Mainnet https://chainlist.org/chain/324
            IZkSyncBridge(ContractsAddress.ZkSyncL2Bridge).withdraw{value: _amount}(
                _to,
                _token,
                _amount
            );
        } else if (Blockchain == 0x1388){
            //Mantle Mainnet
            IERC20(_token).approve(ContractsAddress.MantleL2Bridge, _amount);
            IMantleL2Bridge(ContractsAddress.MantleL2Bridge).withdrawto(
                _token,
                _to,
                _amount,
                MAX_GAS_Limit,
                ""
            );
        }else if (Blockchain == 0xa9) {
            //Manta Pacific Mainnet https://chainlist.org/chain/169
            IERC20(_token).approve(
                ContractsAddress.MantleL2Bridge,
                _amount
            );
            IMantaL2Bridge(ContractsAddress.MantleL2Bridge)
                .withdrawTo{value: _amount}(
                _token,
                _to,
                _amount,
                MAX_GAS_Limit,
                ""
            );
        }
        else if (Blockchain == 0xa70e) {
            // ZKFair https://chainlist.org/chain/42766
            IERC20(_token).approve(
                ContractsAddress.ZKFairL2Bridge,
                _amount
            );
            IPolygonZkEVML2Bridge(ContractsAddress.ZKFairL2Bridge)
                .bridgeAsset(0, _to, _amount, _token, false, "");
        }
        else {
            revert ErrorBlockChain();
        }
        FundingPoolBalance[_token] -= _amount;
        emit WithdrawERC20toL1Success(
            block.chainid,
            block.timestamp,
            _token,
            _to,
            _amount
        );
        return true;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}