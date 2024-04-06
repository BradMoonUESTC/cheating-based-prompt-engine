// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {ERC1155} from "@tokens/ERC1155Minimal.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

contract ERC1155MinimalHarness is ERC1155 {
    function mint(uint256 id, uint256 amount) public {
        _mint(msg.sender, id, amount);
    }

    function mint(address account, uint256 id, uint256 amount) public {
        _mint(account, id, amount);
    }
}

contract ERC1155Minimal is Test {
    ERC1155MinimalHarness token;
    mapping(uint256 => bool) seen;

    function cleanDups(uint256[10] memory x) internal {
        for (uint256 i = 0; i < 10; i++) {
            vm.assume(!seen[x[i]]);
            seen[x[i]] = true;
        }
    }

    function fixedToDynamic(uint256[10] memory x) internal pure returns (uint256[] memory) {
        uint256[] memory y = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            y[i] = x[i];
        }
        return y;
    }

    function fixedToDynamic(address[10] memory x) internal pure returns (address[] memory) {
        address[] memory y = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            y[i] = x[i];
        }
        return y;
    }

    function expand(address value, uint256 size) internal pure returns (address[] memory) {
        address[] memory result = new address[](size);
        for (uint256 i = 0; i < size; i++) {
            result[i] = value;
        }
        return result;
    }

    function setUp() public {
        vm.startPrank(address(1));
        token = new ERC1155MinimalHarness();
    }

    function testSuccess_supportsInterface_ERC165() public {
        assertTrue(token.supportsInterface(0x01ffc9a7));
    }

    function testSuccess_supportsInterface_ERC1155() public {
        assertTrue(token.supportsInterface(0xd9b67a26));
    }

    function testSuccess_supportsInterface_unsupported(bytes4 identifier) public {
        vm.assume(identifier != 0x01ffc9a7);
        vm.assume(identifier != 0xd9b67a26);
        assertTrue(!token.supportsInterface(0xdeadbeef));
    }

    function testSuccess_balanceOfBatch(
        address[10] memory accounts,
        uint256[10] memory ids,
        uint256[10] memory amounts
    ) public {
        cleanDups(ids);
        for (uint256 i = 0; i < accounts.length; i++) {
            vm.assume(accounts[i].code.length == 0);
            token.mint(accounts[i], ids[i], amounts[i]);
        }
        assertEq(
            token.balanceOfBatch(fixedToDynamic(accounts), fixedToDynamic(ids)),
            fixedToDynamic(amounts)
        );
    }

    function testSuccess_safeTransferFrom(address to, uint256 id, uint256 amount) public {
        vm.assume(to.code.length == 0);
        token.mint(id, amount);
        token.safeTransferFrom(address(1), to, id, amount, "");
        assertEq(token.balanceOf(to, id), amount);
    }

    function testFail_safeTransferFrom_insufficientBalance(
        address to,
        uint256 id,
        uint256 amount,
        uint256 transferAmount
    ) public {
        amount = bound(amount, 0, type(uint256).max - 1);
        transferAmount = bound(transferAmount, amount + 1, type(uint256).max);
        vm.assume(to.code.length == 0);
        token.mint(id, amount);
        token.safeTransferFrom(address(1), to, id, transferAmount, "");
    }

    function testFail_safeTransferFrom_unsafeRecipient(uint256 id, uint256 amount) public {
        token.mint(id, amount);
        vm.stopPrank();
        vm.expectRevert("UnsafeRecipient()");
        token.safeTransferFrom(address(1), address(this), id, amount, "");
    }

    function testSuccess_safeBatchTransferFrom(
        address to,
        uint256[10] memory ids,
        uint256[10] memory amounts
    ) public {
        cleanDups(ids);
        vm.assume(to.code.length == 0);
        for (uint256 i = 0; i < ids.length; i++) {
            token.mint(ids[i], amounts[i]);
        }
        token.safeBatchTransferFrom(
            address(1),
            to,
            fixedToDynamic(ids),
            fixedToDynamic(amounts),
            ""
        );

        assertEq(
            token.balanceOfBatch(expand(to, 10), fixedToDynamic(ids)),
            fixedToDynamic(amounts)
        );
    }

    function testFail_safeBatchTransferFrom_insufficientBalance(
        address to,
        uint256[10] memory ids,
        uint256[10] memory amounts,
        uint256[10] memory transferAmounts,
        uint256 index
    ) public {
        vm.assume(to.code.length == 0);

        // make sure at least one of the transfer amounts is too large
        amounts[index] = bound(amounts[index], 0, type(uint256).max - 1);
        transferAmounts[index] = bound(
            transferAmounts[index],
            amounts[index] + 1,
            type(uint256).max
        );
        for (uint256 i = 0; i < ids.length; i++) {
            token.mint(ids[i], amounts[i]);
        }
        vm.expectRevert("InsufficientBalance()");
        token.safeBatchTransferFrom(
            address(1),
            to,
            fixedToDynamic(ids),
            fixedToDynamic(transferAmounts),
            ""
        );
    }

    function testFail_safeTransferFrom_unsafeRecipient(
        uint256[10] memory ids,
        uint256[10] memory amounts
    ) public {
        for (uint256 i = 0; i < ids.length; i++) {
            token.mint(ids[i], amounts[i]);
        }
        vm.stopPrank();
        vm.expectRevert("UnsafeRecipient()");
        token.safeBatchTransferFrom(
            address(1),
            address(this),
            fixedToDynamic(ids),
            fixedToDynamic(amounts),
            ""
        );
    }

    function testSuccess_setApprovalForAll(address approvee, uint256 id, uint256 amount) public {
        token.mint(id, amount);
        token.setApprovalForAll(approvee, true);
        assertTrue(token.isApprovedForAll(address(1), approvee));
    }

    function testSuccess_safeTransferFrom_approved(
        address approvee,
        uint256 id,
        uint256 amount
    ) public {
        vm.assume(approvee.code.length == 0);
        token.mint(id, amount);
        token.setApprovalForAll(approvee, true);
        vm.startPrank(approvee);
        token.safeTransferFrom(address(1), approvee, id, amount, "");
        assertEq(token.balanceOf(approvee, id), amount);
    }

    function testFail_safeTransferFrom_unapproved(
        address approvee,
        uint256 id,
        uint256 amount
    ) public {
        vm.assume(approvee.code.length == 0);
        token.mint(id, amount);
        vm.startPrank(approvee);
        vm.expectRevert("NotAuthorized()");
        token.safeTransferFrom(address(1), approvee, id, amount, "");
    }

    function testSuccess_safeBatchTransferFrom_approved(
        address approvee,
        uint256[10] memory ids,
        uint256[10] memory amounts
    ) public {
        cleanDups(ids);
        vm.assume(approvee.code.length == 0);
        for (uint256 i = 0; i < ids.length; i++) {
            token.mint(ids[i], amounts[i]);
        }
        token.setApprovalForAll(approvee, true);
        vm.startPrank(approvee);
        token.safeBatchTransferFrom(
            address(1),
            approvee,
            fixedToDynamic(ids),
            fixedToDynamic(amounts),
            ""
        );

        assertEq(
            token.balanceOfBatch(expand(approvee, 10), fixedToDynamic(ids)),
            fixedToDynamic(amounts)
        );
    }

    function testFail_safeTransferFrom_unapproved(
        address approvee,
        uint256[10] memory ids,
        uint256[10] memory amounts
    ) public {
        vm.assume(approvee.code.length == 0);
        for (uint256 i = 0; i < ids.length; i++) {
            token.mint(ids[i], amounts[i]);
        }
        vm.startPrank(approvee);
        vm.expectRevert("NotAuthorized()");
        token.safeBatchTransferFrom(
            address(1),
            approvee,
            fixedToDynamic(ids),
            fixedToDynamic(amounts),
            ""
        );
    }
}
