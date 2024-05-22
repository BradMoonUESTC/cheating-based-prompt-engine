methods {
    function numOfController(address account) external returns (uint8) envfree;
}

// CER-41: Account Status Check more than one controller.
// If there is more than one Controller enabled for an Account at the time of 
// the Check, the Account Status MUST always be considered invalid
rule account_status_only_one_controller {
    env e;
    address account;
    require numOfController(account) > 1;
    bool isValid = checkAccountStatus(e, account);
    assert !isValid;
}