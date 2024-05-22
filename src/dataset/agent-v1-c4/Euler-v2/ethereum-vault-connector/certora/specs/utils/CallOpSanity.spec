/**
 * This file collects a few basic checks concerning the sanity of calls out of
 * the EVC contract, making sure they don't give other code access to our
 * storage. There are generally two ways to do this, using `callcode` or
 * `delegatecall`. Thus we check that:
 * - `callcode` should not be used
 * - `delegatecall` should only call directly into `currentContract`
 *
 * This implies that whenever we call other code (via `call` or `staticcall`)
 * that code has no (write) access to our storage. Furthermore, any reentrant
 * call (with write access) comes with `msg.sender != currentContract`.
 */

hook CALLCODE(uint g, address addr, uint value, uint argsOffset, uint argsLength, uint retOffset, uint retLength) uint rc
{
    assert(executingContract != currentContract,
        "we should not use `callcode`"
    );
}

hook DELEGATECALL(uint g, address addr, uint argsOffset, uint argsLength, uint retOffset, uint retLength) uint rc
{
    assert(executingContract != currentContract || addr == currentContract,
        "we should only `delegatecall` into ourselves"
    );
}
