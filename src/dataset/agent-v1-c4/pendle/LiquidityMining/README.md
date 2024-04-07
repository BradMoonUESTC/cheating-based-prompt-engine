# vePendle For Launch

### Locking PENDLE for vePendle (on ETH)

- Each user can only lock for a maximum of $MAXLOCKTIME$ = 2 years
- vePendle balance for users is represented by:
  $balance_u(t) = bias_u - slope_u * t$

- As such, we just need to store $bias_u$ and $slope_u$ for each user. (Considerations: store $bias_u$ and $t_{expiry}$ for the user instead, because $t_{expiry}$ is always an exact number)
- The amount of PENDLE locked by user $u$ is $locked_u$
- For total supply, it's simply $totalBalance = totalBias - totalSlope * t$
- Possible actions by an user:
  - User $u$ create a new lock by locking $d_{PENDLE}$ of PENDLE tokens, expiring at $t_{expiry}$
    $slope_u = d_{PENDLE} / MAXLOCKTIME$
    $bias_u = slope_u \cdot t_{expiry}$
  - User $u$ locks an additional of $d_{PENDLE}$ PENDLE tokens, into his existing lock expiring at $t_{expiry}$
    $slope_{u_{new}} = slope_u + d_{PENDLE} / MAXLOCKTIME$
    $bias_{u_{new}} = slope_{u_{new}} \cdot t_{expiry}$
  - User $u$ extends his expiry from $t_{expiry}$ to $t_{expiry_{new}}$
    $bias_{u_{new}} = slope_{u} \cdot t_{expiry_{new}}$
- Similar to Curve:
  - We store the checkpoints for when a user's $slope$ or $bias$ changes
  - We restrict the possible expiries to exact weeks from UNIX timestamp 0
  - We store the global bias and slope changes due to expiry of user's vote-locks per week, and process it when the week comes

### Cross-chain messaging module

- There are contracts inheritting `CelerSender` on governance chain - Ethereum, with a function `sendMessage(chain Y, sender, message)` to send messages to other chains.
- On each non-governance chain, we have contracts inheritting `CelerReceiver`. Each has a function `afterReceivingMessage(sender, message)` to receive the message from governance.
- When `sendMessage(chain Y, sender, message)` is called on governance chain, `afterReceivingMessage(sender, message)` will be called on chain Y, thanks to the cross-chain messaging module
- The current mechanics for the module is using Celer
- The cross-chain messaging module can be plugged in/plugged out by the governance address (which will initially be controlled by a team multisig)

### Voting for incentives on market and chains

- On Ethereum, there is a `VotingController` contract to control the voting on incentives for the different markets on the different chains.
- Adding a new chain:
  - Only the governance address will be able to add markets and a new chains' GaugeController.
- There is a list of `(market)` that are elligible for the voting, added by governance
  - markets that are expired will be removed by governance
- vePendle holders can allocate their vePendle to multiple markets on multiple chains
- Similar to Curve, we store the bias and slope of the total vePendle voted for every market
  - Similary, we adjust the slope/bias changes due to expired vePendle at the weekly mark
- There is a global PENDLE per second rate for all the incentives across all the chains. This is set by governance.
- The `VotingController` does not hold any fund. The incentivizing PENDLE is transferred directly to GaugeController by governacne. \* GaugeControllers: admin can withdraw PENDLE from it
- In each chain, there is a `GaugeController` contract that is responsible for keeping PENDLE incentives and distributing PENDLE to incentivise different markets.
- At the finalization of each week (starting of new week), anyone can call a function `finalizeVotingResults` and then `broadcastVotes()` in `VotingController` to broadcast to any chain:
  1. The PENDLE allocation of each market for the next week
  2. The timestamp to mark which week is the incentivization coming from
     When this happens, the `GaugeController` in each chain will update the PENDLE per second among the different markets
- At any time, the governacne has the voting power equivalent to locking X PENDLE in 2 years

### GaugeController

Gauge controller will receive the voting results from VotingController and incentivize the amount of PENDLE from `block.timestamp` to `block.timestamp + 1 WEEK`.

If there is still leftover reward in each pool, the gauge controller will remove and take the leftover to top up the incentivize for the current week.

### Gauge & Market

- The Gauge/Market will receive rewardTokens from SCY as well as claiming the PENDLE token from gauge controller. All of the reward tokens (including PENDLE) will be distributed with boosting mechanism

### Broadcasting vePendle balance & different address for boosting rewards for each chain

- At anytime, an address A could send a cross message to update the vePendle balance on a specific chain
- The governance reserves the right to set the vePENDLE delegator for some address (for other protocols to build on top).
