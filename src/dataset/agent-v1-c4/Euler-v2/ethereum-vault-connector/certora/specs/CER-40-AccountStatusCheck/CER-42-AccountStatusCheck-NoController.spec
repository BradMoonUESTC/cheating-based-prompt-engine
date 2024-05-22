methods {
    function numOfController(address account) external returns (uint8) envfree;
}

// CER-42: Account Status Check no controller
// If there is no Controller enabled for an Account at the time of the Check, 
// the Account Status MUST always be considered valid. It includes disabling 
// the only enabled Controller before the Checks.
rule account_status_no_controller {
    env e;
    address account;
    require numOfController(account) == 0;
    bool isValid = checkAccountStatus(e, account);
    assert isValid;
}