
methods{
    function getAddressPrefix(address) external returns (bytes19) envfree;
    function haveCommonOwner(address, address) external returns (bool) envfree;
}

//check that two addresses with the same prefix also have a common owner
rule check_have_commonPrefix(){
    address x;
    address y;
    bytes19 prefixX = getAddressPrefix(x);
    bytes19 prefixY = getAddressPrefix(y);

    bool haveCommonOwner = haveCommonOwner(x,y);

    assert haveCommonOwner <=> prefixX == prefixY;
}
