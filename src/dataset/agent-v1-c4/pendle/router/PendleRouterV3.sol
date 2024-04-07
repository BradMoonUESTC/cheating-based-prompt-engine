// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/proxy/Proxy.sol";
import "../interfaces/IPAllActionV3.sol";
import "../interfaces/IDiamondLoupe.sol";
import "../interfaces/IDiamondCut.sol";

// solhint-disable no-empty-blocks
contract PendleRouterV3 is Proxy, IDiamondLoupe {
    address internal immutable ACTION_ADD_REMOVE_LIQ;
    address internal immutable ACTION_SWAP_PT;
    address internal immutable ACTION_SWAP_YT;
    address internal immutable ACTION_MISC;
    address internal immutable ACTION_CALLBACK;

    event DiamondCut(IDiamondCut.FacetCut[] _diamondCut, address _init, bytes _calldata);

    constructor(
        address _ACTION_ADD_REMOVE_LIQ,
        address _ACTION_SWAP_PT,
        address _ACTION_SWAP_YT,
        address _ACTION_MISC,
        address _ACTION_CALLBACK
    ) {
        ACTION_ADD_REMOVE_LIQ = _ACTION_ADD_REMOVE_LIQ;
        ACTION_SWAP_PT = _ACTION_SWAP_PT;
        ACTION_SWAP_YT = _ACTION_SWAP_YT;
        ACTION_MISC = _ACTION_MISC;
        ACTION_CALLBACK = _ACTION_CALLBACK;
        _emitEvents();
    }

    function _emitEvents() internal {
        Facet[] memory facets_ = facets();

        uint256 nFacets = facets_.length;

        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](nFacets);
        for (uint256 i; i < nFacets; ) {
            cuts[i].facetAddress = facets_[i].facetAddress;
            cuts[i].action = IDiamondCut.FacetCutAction.Add;
            cuts[i].functionSelectors = facets_[i].functionSelectors;
            unchecked {
                ++i;
            }
        }

        emit DiamondCut(cuts, address(0), "");
    }

    receive() external payable virtual override {}

    /// @notice Gets all facet addresses and their four byte function selectors.
    /// @return facets_ Facet
    function facets() public view returns (Facet[] memory facets_) {
        address[] memory facetAddresses_ = facetAddresses();
        uint256 numFacets = facetAddresses_.length;

        facets_ = new Facet[](numFacets);
        for (uint256 i; i < numFacets; ) {
            facets_[i].facetAddress = facetAddresses_[i];
            facets_[i].functionSelectors = facetFunctionSelectors(facetAddresses_[i]);
            unchecked {
                i++;
            }
        }
    }

    function facetFunctionSelectors(address facet) public view returns (bytes4[] memory res) {
        if (facet == address(this)) {
            res = new bytes4[](4);
            res[0] = 0x52ef6b2c; // facetAddresses
            res[1] = 0x7a0ed627; // facets
            res[2] = 0xadfca15e; // facetFunctionSelectors
            res[3] = 0xcdffacc6; // facetAddress
        }
        if (facet == ACTION_ADD_REMOVE_LIQ) {
            res = new bytes4[](12);
            res[0] = 0x12599ac6; // addLiquiditySingleToken
            res[1] = 0x2756ce06; // addLiquidityDualTokenAndPt
            res[2] = 0x3dbe1c55; // addLiquiditySingleTokenKeepYt
            res[3] = 0x4e390267; // addLiquiditySinglePt
            res[4] = 0x58bda475; // addLiquiditySingleSy
            res[5] = 0x60da0860; // removeLiquiditySingleToken
            res[6] = 0x6b77ac9e; // removeLiquiditySinglePt
            res[7] = 0x844384aa; // addLiquiditySingleSyKeepYt
            res[8] = 0x97ee279e; // addLiquidityDualSyAndPt
            res[9] = 0xb00f09d7; // removeLiquidityDualTokenAndPt
            res[10] = 0xb7d75b8b; // removeLiquidityDualSyAndPt
            res[11] = 0xd13b4fdc; // removeLiquiditySingleSy
        }
        if (facet == ACTION_SWAP_YT) {
            res = new bytes4[](6);
            res[0] = 0x05eb5327; // swapExactYtForToken
            res[1] = 0x448b9b95; // swapExactYtForPt
            res[2] = 0x7b8b4b95; // swapExactSyForYt
            res[3] = 0x80c4d566; // swapExactYtForSy
            res[4] = 0xc861a898; // swapExactPtForYt
            res[5] = 0xed48907e; // swapExactTokenForYt
        }
        if (facet == ACTION_SWAP_PT) {
            res = new bytes4[](4);
            res[0] = 0x2a50917c; // swapExactSyForPt
            res[1] = 0x3346d3a3; // swapExactPtForSy
            res[2] = 0x594a88cc; // swapExactPtForToken
            res[3] = 0xc81f847a; // swapExactTokenForPt
        }
        if (facet == ACTION_CALLBACK) {
            res = new bytes4[](2);
            res[0] = 0xeb3a7d47; // limitRouterCallback
            res[1] = 0xfa483e72; // swapCallback
        }
        if (facet == ACTION_MISC) {
            res = new bytes4[](12);
            res[0] = 0x1a8631b2; // mintPyFromSy
            res[1] = 0x2d8f9d8d; // boostMarkets
            res[2] = 0x2e071dc6; // mintSyFromToken
            res[3] = 0x339748cb; // redeemPyToSy
            res[4] = 0x339a5572; // redeemSyToToken
            res[5] = 0x47f1de22; // redeemPyToToken
            res[6] = 0x5d3e105c; // swapTokenToToken
            res[7] = 0x60fc8466; // multicall
            res[8] = 0xa89eba4a; // swapTokenToTokenViaSy
            res[9] = 0xbd61951d; // simulate
            res[10] = 0xd0f42385; // mintPyFromToken
            res[11] = 0xf7e375e8; // redeemDueInterestAndRewards
        }
    }

    function facetAddress(bytes4 sig) public view returns (address) {
        if (sig < 0x6b77ac9e) {
            if (sig < 0x3dbe1c55) {
                if (sig < 0x2d8f9d8d) {
                    if (sig < 0x1a8631b2) {
                        if (sig == 0x05eb5327) return ACTION_SWAP_YT; //swapExactYtForToken
                        if (sig == 0x12599ac6) return ACTION_ADD_REMOVE_LIQ; //addLiquiditySingleToken
                    } else {
                        if (sig == 0x1a8631b2) return ACTION_MISC; //mintPyFromSy
                        if (sig == 0x2756ce06) return ACTION_ADD_REMOVE_LIQ; //addLiquidityDualTokenAndPt
                        if (sig == 0x2a50917c) return ACTION_SWAP_PT; //swapExactSyForPt
                    }
                } else {
                    if (sig < 0x3346d3a3) {
                        if (sig == 0x2d8f9d8d) return ACTION_MISC; //boostMarkets
                        if (sig == 0x2e071dc6) return ACTION_MISC; //mintSyFromToken
                    } else {
                        if (sig == 0x3346d3a3) return ACTION_SWAP_PT; //swapExactPtForSy
                        if (sig == 0x339748cb) return ACTION_MISC; //redeemPyToSy
                        if (sig == 0x339a5572) return ACTION_MISC; //redeemSyToToken
                    }
                }
            } else {
                if (sig < 0x58bda475) {
                    if (sig < 0x47f1de22) {
                        if (sig == 0x3dbe1c55) return ACTION_ADD_REMOVE_LIQ; //addLiquiditySingleTokenKeepYt
                        if (sig == 0x448b9b95) return ACTION_SWAP_YT; //swapExactYtForPt
                    } else {
                        if (sig == 0x47f1de22) return ACTION_MISC; //redeemPyToToken
                        if (sig == 0x4e390267) return ACTION_ADD_REMOVE_LIQ; //addLiquiditySinglePt
                        if (sig == 0x52ef6b2c) return address(this); //facetAddresses
                    }
                } else {
                    if (sig < 0x5d3e105c) {
                        if (sig == 0x58bda475) return ACTION_ADD_REMOVE_LIQ; //addLiquiditySingleSy
                        if (sig == 0x594a88cc) return ACTION_SWAP_PT; //swapExactPtForToken
                    } else {
                        if (sig == 0x5d3e105c) return ACTION_MISC; //swapTokenToToken
                        if (sig == 0x60da0860) return ACTION_ADD_REMOVE_LIQ; //removeLiquiditySingleToken
                        if (sig == 0x60fc8466) return ACTION_MISC; //multicall
                    }
                }
            }
        } else {
            if (sig < 0xbd61951d) {
                if (sig < 0x97ee279e) {
                    if (sig < 0x7b8b4b95) {
                        if (sig == 0x6b77ac9e) return ACTION_ADD_REMOVE_LIQ; //removeLiquiditySinglePt
                        if (sig == 0x7a0ed627) return address(this); //facets
                    } else {
                        if (sig == 0x7b8b4b95) return ACTION_SWAP_YT; //swapExactSyForYt
                        if (sig == 0x80c4d566) return ACTION_SWAP_YT; //swapExactYtForSy
                        if (sig == 0x844384aa) return ACTION_ADD_REMOVE_LIQ; //addLiquiditySingleSyKeepYt
                    }
                } else {
                    if (sig < 0xadfca15e) {
                        if (sig == 0x97ee279e) return ACTION_ADD_REMOVE_LIQ; //addLiquidityDualSyAndPt
                        if (sig == 0xa89eba4a) return ACTION_MISC; //swapTokenToTokenViaSy
                    } else {
                        if (sig == 0xadfca15e) return address(this); //facetFunctionSelectors
                        if (sig == 0xb00f09d7) return ACTION_ADD_REMOVE_LIQ; //removeLiquidityDualTokenAndPt
                        if (sig == 0xb7d75b8b) return ACTION_ADD_REMOVE_LIQ; //removeLiquidityDualSyAndPt
                    }
                }
            } else {
                if (sig < 0xd13b4fdc) {
                    if (sig < 0xc861a898) {
                        if (sig == 0xbd61951d) return ACTION_MISC; //simulate
                        if (sig == 0xc81f847a) return ACTION_SWAP_PT; //swapExactTokenForPt
                    } else {
                        if (sig == 0xc861a898) return ACTION_SWAP_YT; //swapExactPtForYt
                        if (sig == 0xcdffacc6) return address(this); //facetAddress
                        if (sig == 0xd0f42385) return ACTION_MISC; //mintPyFromToken
                    }
                } else {
                    if (sig < 0xed48907e) {
                        if (sig == 0xd13b4fdc) return ACTION_ADD_REMOVE_LIQ; //removeLiquiditySingleSy
                        if (sig == 0xeb3a7d47) return ACTION_CALLBACK; //limitRouterCallback
                    } else {
                        if (sig == 0xed48907e) return ACTION_SWAP_YT; //swapExactTokenForYt
                        if (sig == 0xf7e375e8) return ACTION_MISC; //redeemDueInterestAndRewards
                        if (sig == 0xfa483e72) return ACTION_CALLBACK; //swapCallback
                    }
                }
            }
        }
        revert Errors.RouterInvalidAction(sig);
        // NUM_FUNC: 40 AVG:4.80 WORST_CASE:6 STOP_BRANCH:3
    }

    function facetAddresses() public view returns (address[] memory) {
        address[] memory res = new address[](6);
        res[0] = address(this);
        res[1] = ACTION_ADD_REMOVE_LIQ;
        res[2] = ACTION_SWAP_YT;
        res[3] = ACTION_SWAP_PT;
        res[4] = ACTION_CALLBACK;
        res[5] = ACTION_MISC;
        return res;
    }

    function _implementation() internal view override returns (address) {
        return facetAddress(msg.sig);
    }
}
