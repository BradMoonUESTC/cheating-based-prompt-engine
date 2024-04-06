// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {PanopticMath} from "@libraries/PanopticMath.sol";
import {TokenId} from "@types/TokenId.sol";
import "../core/SemiFungiblePositionManager.t.sol";

contract ReenterBurn {
    // ensure storage conflicts don't occur with etched contract
    uint256[65535] private __gap;

    struct Slot0 {
        // the current price
        uint160 sqrtPriceX96;
        // the current tick
        int24 tick;
        // the most-recently updated index of the observations array
        uint16 observationIndex;
        // the current maximum number of observations that are being stored
        uint16 observationCardinality;
        // the next maximum number of observations to store, triggered in observations.write
        uint16 observationCardinalityNext;
        // the current protocol fee as a percentage of the swap fee taken on withdrawal
        // represented as an integer denominator (1/x)%
        uint8 feeProtocol;
        // whether the pool is locked
        bool unlocked;
    }

    Slot0 public slot0;

    int24 public tickSpacing;

    address public token0;
    address public token1;
    uint24 public fee;

    bool activated;

    function construct(
        Slot0 memory _slot0,
        address _token0,
        address _token1,
        uint24 _fee,
        int24 _tickSpacing
    ) public {
        slot0 = _slot0;
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
        tickSpacing = _tickSpacing;
    }

    fallback() external {
        bool reenter = !activated;
        activated = true;
        if (reenter)
            SemiFungiblePositionManagerHarness(msg.sender).burnTokenizedPosition(
                TokenId.wrap(0).addPoolId(PanopticMath.getPoolId(address(this))),
                0,
                0,
                0
            );
    }
}

contract ReenterMint {
    // ensure storage conflicts don't occur with etched contract
    uint256[65535] private __gap;

    struct Slot0 {
        // the current price
        uint160 sqrtPriceX96;
        // the current tick
        int24 tick;
        // the most-recently updated index of the observations array
        uint16 observationIndex;
        // the current maximum number of observations that are being stored
        uint16 observationCardinality;
        // the next maximum number of observations to store, triggered in observations.write
        uint16 observationCardinalityNext;
        // the current protocol fee as a percentage of the swap fee taken on withdrawal
        // represented as an integer denominator (1/x)%
        uint8 feeProtocol;
        // whether the pool is locked
        bool unlocked;
    }

    Slot0 public slot0;

    int24 public tickSpacing;

    address public token0;
    address public token1;
    uint24 public fee;

    bool activated;

    function construct(
        Slot0 memory _slot0,
        address _token0,
        address _token1,
        uint24 _fee,
        int24 _tickSpacing
    ) public {
        slot0 = _slot0;
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
        tickSpacing = _tickSpacing;
    }

    fallback() external {
        bool reenter = !activated;
        activated = true;

        if (reenter)
            SemiFungiblePositionManagerHarness(msg.sender).mintTokenizedPosition(
                TokenId.wrap(0).addPoolId(PanopticMath.getPoolId(address(this))),
                0,
                0,
                0
            );
    }
}

contract ReenterTransferSingle {
    // ensure storage conflicts don't occur with etched contract
    uint256[65535] private __gap;

    struct Slot0 {
        // the current price
        uint160 sqrtPriceX96;
        // the current tick
        int24 tick;
        // the most-recently updated index of the observations array
        uint16 observationIndex;
        // the current maximum number of observations that are being stored
        uint16 observationCardinality;
        // the next maximum number of observations to store, triggered in observations.write
        uint16 observationCardinalityNext;
        // the current protocol fee as a percentage of the swap fee taken on withdrawal
        // represented as an integer denominator (1/x)%
        uint8 feeProtocol;
        // whether the pool is locked
        bool unlocked;
    }

    Slot0 public slot0;

    int24 public tickSpacing;

    address public token0;
    address public token1;
    uint24 public fee;

    bool activated;

    function construct(
        Slot0 memory _slot0,
        address _token0,
        address _token1,
        uint24 _fee,
        int24 _tickSpacing
    ) public {
        slot0 = _slot0;
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
        tickSpacing = _tickSpacing;
    }

    fallback() external {
        bool reenter = !activated;
        activated = true;

        if (reenter)
            SemiFungiblePositionManagerHarness(msg.sender).safeTransferFrom(
                address(0),
                address(0),
                TokenId.unwrap(TokenId.wrap(0).addPoolId(PanopticMath.getPoolId(address(this)))),
                0,
                ""
            );
    }
}

contract ReenterTransferBatch {
    // ensure storage conflicts don't occur with etched contract
    uint256[65535] private __gap;

    struct Slot0 {
        // the current price
        uint160 sqrtPriceX96;
        // the current tick
        int24 tick;
        // the most-recently updated index of the observations array
        uint16 observationIndex;
        // the current maximum number of observations that are being stored
        uint16 observationCardinality;
        // the next maximum number of observations to store, triggered in observations.write
        uint16 observationCardinalityNext;
        // the current protocol fee as a percentage of the swap fee taken on withdrawal
        // represented as an integer denominator (1/x)%
        uint8 feeProtocol;
        // whether the pool is locked
        bool unlocked;
    }

    Slot0 public slot0;

    int24 public tickSpacing;

    address public token0;
    address public token1;
    uint24 public fee;

    bool activated;

    function construct(
        Slot0 memory _slot0,
        address _token0,
        address _token1,
        uint24 _fee,
        int24 _tickSpacing
    ) public {
        slot0 = _slot0;
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
        tickSpacing = _tickSpacing;
    }

    fallback() external {
        bool reenter = !activated;
        activated = true;

        uint256[] memory ids = new uint256[](1);
        ids[0] = TokenId.unwrap(TokenId.wrap(0).addPoolId(PanopticMath.getPoolId(address(this))));
        if (reenter)
            SemiFungiblePositionManagerHarness(msg.sender).safeBatchTransferFrom(
                address(0),
                address(0),
                ids,
                new uint256[](1),
                ""
            );
    }
}

// through ERC1155 transfer
contract Reenter1155Initialize {
    address public token0;
    address public token1;
    uint24 public fee;
    uint64 poolId;

    bool activated;

    function construct(address _token0, address _token1, uint24 _fee, uint64 _poolId) public {
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
        poolId = _poolId;
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public returns (bytes4) {
        bool reenter = !activated;
        activated = true;

        if (reenter)
            SemiFungiblePositionManagerHarness(msg.sender).initializeAMMPool(token0, token1, fee);
        if (reenter)
            SemiFungiblePositionManagerHarness(msg.sender).mintTokenizedPosition(
                TokenId.wrap(poolId),
                0,
                0,
                0
            );
        return this.onERC1155Received.selector;
    }
}
