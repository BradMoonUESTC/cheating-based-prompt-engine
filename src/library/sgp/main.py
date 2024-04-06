import sgp_parser

def main():
    input = """
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract X {

    function a() public pure returns (uint) {        
        return 1;
    }

}
    """
    try:
        ast = sgp_parser.parse(input, dump_json=True)
        print(ast)
    except Exception as e:
        print(e)

if __name__ == '__main__':
    main()
