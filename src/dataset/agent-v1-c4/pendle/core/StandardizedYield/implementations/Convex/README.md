# PENDLE Curve/Convex SY

For the simplicity of the writeup, we will describe only the noticable properties of `PendleCurveUSDD3CrvSY`. `PendleCurveFraxUsdcSY` contract should contain only a subset of those properties compared to USDD one.

## Token in/out flow

We support USDD/USDC/DAI/USDT and the two LPs as in and out tokens. Tokens after being deposited to Curve to get back LP USDD/3Crv will be staked into Convex reward system to gain rewards of:

- USDD
- CRV
- CVX

![](https://i.ibb.co/9rgWfvg/curve.png)

## Exchange Rate

Asset type for this SY should be in type of Liquidity. For exchange rate, we use Curve's `pool.get_virtual_price()` as it shows the growth in price of LP token respecting to the swap fees earned by the pool.

## Preview functions

Before getting to this, we would like to note that preview functions will play an important role in Pendle's off-chain system. Hence, it is essential for preview function returns the actual outcome that user can get by calling `deposit/redeem`.

For preview redeem, Curve provides a view function of `calc_withdraw_one_coin` which accurately returns the amount of token can be redeem by user with a particular amount of LP.

For previde deposit, Curve's provided function `calc_token_amount` does not take into account the fee, thus, it does not return the actual amount of lp token user can get.

We implemented a workaround for previewDeposit in `CurveUsdd3CrvPoolHelper` and `Curve3CrvPoolHelper` to simulate the calculation happened in Curve's code base.

Another thing to note is that `CurveUsdd3CrvPoolHelper`'s preivew deposit result has a dependency on the `3crv.get_virtual_price`. So the simulation should also take into account the case when user deposits with DAI/USDC/USDT, the state of 3Crv pool changes, and thus the `get_virtual_price` of 3crv changes.
