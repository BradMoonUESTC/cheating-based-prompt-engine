//   _____    ______   ____     ____   __   __
//  |  __ \  |  ____| |  _ \   / __ \  \ \ / /
//  | |  | | | |__    | |_) | | |  | |  \ V /
//  | |  | | |  __|   |  _ <  | |  | |   > <
//  | |__| | | |____  | |_) | | |__| |  / . \
//  |_____/  |______| |____/   \____/  /_/ \_\
//
//  Author: https://debox.pro/
//

// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title DBXLockup is a contract to lock DBX for a period of time
 * @author https://debox.pro/
 * @dev DBXLockup is a contract to lock DBX for a period of time, and release it by the beneficiary.
 * 1. the lock amount will be released by the beneficiary, and can't be released by the contract owner.
 * 2. if beneficiary loses the private key, the DBX will be locked forever!
 * 3. MUST accept lockup before lock. it can safely allow/disallow lockup to prevent new lockup, but can't disallow existing lockup.
 * 4. the lock amount will be transferred from msg.sender to this contract, and will be released by the beneficiary.
 */
contract DBXLockup {
  using SafeERC20 for IERC20;

  event Released(address indexed beneficiary, uint256 amount);
  event Lockup(address indexed beneficiary, uint256 amount, uint256 interval, uint256 releaseTimes);
  event AcceptLockup(address indexed beneficiary, bool ok);

  uint256 private constant _ONE = 1e18;
  IERC20 public immutable dbx;
  mapping(address => Lock[]) public locked;
  mapping(address => bool) public canLock;

  struct Lock {
    uint256 lockAmount;
    uint256 interval;
    uint256 oneReleaseAmount;
    uint256 nextReleaseAt;
  }

  constructor(address _dbx) {
    require(_dbx != address(0), "DBXLockup: invalid DBX address");
    dbx = IERC20(_dbx);
  }

  /**
   * @notice get the total and releaseable amount of the beneficiary
   * @param beneficiary is the beneficiary address
   * @return total return the total locked amount of the beneficiary
   * @return releaseable return the releaseable amount of the beneficiary
   */
  function balanceOf(address beneficiary) public view returns (uint256 total, uint256 releaseable) {
    for (uint256 i = 0; i < locked[beneficiary].length; i++) {
      Lock storage item = locked[beneficiary][i];
      total += item.lockAmount;
      releaseable += _calculate(item);
    }
  }

  /**
   * @notice beneficiary can allow or disallow lockup
   * @dev it can safely allow/disallow lockup to prevent new lockup, but can't disallow existing lockup.
   * @param ok is the flag to allow or disallow lockup
   */
  function acceptLockup(bool ok) external {
    require(canLock[msg.sender] != ok, "DBXLockup: already set");
    canLock[msg.sender] = ok;
    emit AcceptLockup(msg.sender, ok);
  }

  /**
   * @notice lock DBX
   * @dev the lock amount will be transferred from msg.sender to this contract, and will be released by the beneficiary.
   * if beneficiary loses the private key, the DBX will be locked forever!
   * @param beneficiary is the beneficiary address
   * @param lockAmount is the amount of DBX to lock, MUST be greater than 10000 DBX
   * @param interval is the interval of each release, in seconds, MUST be greater than 1 hour.
   * @param releaseTimes is the release times, MUST be greater than 1
   */
  function lock(address beneficiary, uint256 lockAmount, uint256 interval, uint256 releaseTimes) external {
    require(canLock[beneficiary], "DBXLockup: not allowed to lock");
    require(locked[beneficiary].length <= 16, "DBXLockup: lock limit reached"); // only allow 16 locks per address
    require(interval >= 1 hours && interval <= 365 days, "DBXLockup: interval invalid");
    require(releaseTimes >= 1 && releaseTimes * interval <= 5 * 365 days, "DBXLockup: release times invalid");
    require(lockAmount >= 10000 * _ONE, "DBXLockup: lock amount too low");

    uint256 oneReleaseAmount = lockAmount / releaseTimes;
    require(oneReleaseAmount >= _ONE, "DBXLockup: release amount too low");

    // transfer
    dbx.safeTransferFrom(msg.sender, address(this), lockAmount);

    // add lock
    locked[beneficiary].push(
      Lock({
        lockAmount: lockAmount,
        interval: interval,
        oneReleaseAmount: oneReleaseAmount,
        nextReleaseAt: block.timestamp + interval
      })
    );

    emit Lockup(beneficiary, lockAmount, interval, releaseTimes);
  }

  /**
   * @notice release the releaseable amount
   * @dev only the beneficiary can release DBX.
   */
  function release() external {
    uint256 releaseable;
    address beneficiary = msg.sender;

    // check and release
    for (uint256 i = 0; i < locked[beneficiary].length; i++) {
      Lock storage item = locked[beneficiary][i];
      uint256 ant = _calculate(item);
      if (ant > 0) {
        releaseable += ant;
        // update lock
        item.lockAmount -= ant;
        uint256 releaseTimes = (block.timestamp - item.nextReleaseAt) / item.interval + 1;
        item.nextReleaseAt += releaseTimes * item.interval;

        // remove empty lock,but keep the first one.
        if (item.lockAmount == 0 && i > 0) {
          if (i == locked[beneficiary].length - 1) {
            locked[beneficiary].pop();
          } else {
            locked[beneficiary][i] = locked[beneficiary][locked[beneficiary].length - 1];
            locked[beneficiary].pop();
            i--;
          }
        }
      }
    }
    require(releaseable > 0, "DBXLockup: no releaseable amount");
    dbx.safeTransfer(beneficiary, releaseable);
    emit Released(beneficiary, releaseable);
  }

  // @dev calculate the releaseable amount
  function _calculate(Lock storage item) private view returns (uint256) {
    if (block.timestamp < item.nextReleaseAt) return 0;
    unchecked {
      uint256 balance = item.lockAmount;
      if (balance < 2 * item.oneReleaseAmount) {
        return balance;
      }
      uint256 releaseTimes = (block.timestamp - item.nextReleaseAt) / item.interval + 1;
      uint256 releaseable = item.oneReleaseAmount * releaseTimes;
      return releaseable > balance ? balance : releaseable;
    }
  }
}
