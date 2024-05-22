methods {
    function isControllerEnabled(address account, address vault) external returns (bool) envfree;
}

// CER-81: EVC MUST NOT be allowed to become Controller
// Note: this does not work for batch or call because these involve
// CALLs which are complicated to reason about
invariant evc_cannot_become_controller(address account)
    !isControllerEnabled(account, currentContract)
    filtered {
        f -> f.selector != sig:batch(IEVC.BatchItem[] calldata).selector
        && f.selector != sig:call(address, address, uint256, bytes calldata).selector
    }

