// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract UniPoolPriceMock {
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

    function updatePrice(int24 _tick) public {
        slot0.tick = _tick;
    }

    function mint(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) public returns (uint256 amount0, uint256 amount1) {}

    function increaseObservationCardinalityNext(uint16 observationCardinalityNext) public {}
}

contract UniPoolObservationMock {
    struct Observation {
        // the block timestamp of the observation
        uint32 blockTimestamp;
        // the tick accumulator, i.e. tick * time elapsed since the pool was first initialized
        int56 tickCumulative;
        // the seconds per liquidity, i.e. seconds elapsed / max(1, liquidity) since the pool was first initialized
        uint160 secondsPerLiquidityCumulativeX128;
        // whether or not the observation is initialized
        bool initialized;
    }

    Observation[] public observations;

    constructor(uint256 cardinality) {
        for (uint256 i = 0; i < cardinality; i++) {
            observations.push(Observation(0, 0, 0, true));
        }
    }

    function setObservation(uint256 idx, uint32 blockTimestamp, int56 tickCumulative) public {
        observations[idx] = Observation({
            blockTimestamp: blockTimestamp,
            tickCumulative: tickCumulative,
            secondsPerLiquidityCumulativeX128: 0,
            initialized: true
        });
    }
}
