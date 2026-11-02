// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IMDwindowshopper} from "../src/IMDwindowshopper.sol";

/// @dev All actors are local test accounts. Amounts are base units, never whole-token approximations.
/// forge-config: default.fuzz.runs = 1024
contract IMDwindowshopperPropertiesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    IMDwindowshopper internal token;
    address internal alice;
    address internal bob;
    address internal spender;

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        token = new IMDwindowshopper();
        alice = makeAddr("property holder alice");
        bob = makeAddr("property holder bob");
        spender = makeAddr("property spender");
    }

    function testFuzz_repeatedApprovalIsIdempotentAndIsolated(uint256 value) public {
        assertTrue(token.transfer(alice, SUPPLY / 3));
        assertTrue(token.approve(spender, 7));
        vm.prank(alice);
        assertTrue(token.approve(bob, 11));

        for (uint256 i; i < 2; ++i) {
            vm.expectEmit(true, true, false, true, address(token));
            emit Approval(alice, spender, value);
            vm.prank(alice);
            assertTrue(token.approve(spender, value));
            assertEq(token.allowance(alice, spender), value);
            assertEq(token.allowance(alice, bob), 11);
            assertEq(token.allowance(address(this), spender), 7);
            assertEq(token.allowance(spender, alice), 0);
            assertEq(token.balanceOf(alice), SUPPLY / 3);
            assertEq(token.balanceOf(address(this)), SUPPLY - SUPPLY / 3);
            assertEq(token.balanceOf(spender), 0);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function test_largestFiniteAllowanceDecreasesByOne() public {
        _checkLargestFiniteAllowance(1);
    }

    function testFuzz_largestFiniteAllowanceIsNotInfinite(uint256 value) public {
        _checkLargestFiniteAllowance(bound(value, 1, SUPPLY));
    }

    function _checkLargestFiniteAllowance(uint256 value) internal {
        uint256 allowed = type(uint256).max - 1;
        assertTrue(token.approve(spender, allowed));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, value));
        assertEq(token.allowance(address(this), spender), allowed - value);
        assertEq(token.balanceOf(alice), value);
        assertEq(token.balanceOf(address(this)), SUPPLY - value);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteApprovalCanBeReducedAndRevokedAfterUse() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        assertTrue(token.approve(spender, 2));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), 1);

        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
    }

    /// @dev Splitting a transfer, or using an approved spender, cannot introduce fees or rounding dust.
    function testFuzz_splitDelegatedSpendingMatchesOneDirectTransfer(uint256 total, uint256 first) public {
        total = bound(total, 0, SUPPLY);
        first = bound(first, 0, total);
        IMDwindowshopper referenceToken = new IMDwindowshopper();
        assertTrue(referenceToken.transfer(alice, total));
        assertTrue(token.approve(spender, total));

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, first));
        assertEq(token.allowance(address(this), spender), total - first);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, total - first));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), referenceToken.balanceOf(address(this)));
        assertEq(token.balanceOf(alice), referenceToken.balanceOf(alice));
        assertEq(token.balanceOf(alice), total);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_partialTransferRoundTripPreservesExistingBalances(uint256 existing, uint256 value) public {
        existing = bound(existing, 0, SUPPLY);
        value = bound(value, 0, SUPPLY - existing);
        assertTrue(token.transfer(alice, existing));
        assertTrue(token.approve(spender, type(uint256).max));

        assertTrue(token.transfer(alice, value));
        assertEq(token.balanceOf(alice), existing + value);
        assertEq(token.balanceOf(address(this)), SUPPLY - existing - value);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), value));
        assertEq(token.balanceOf(alice), existing);
        assertEq(token.balanceOf(address(this)), SUPPLY - existing);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_failedApprovedTransferPreservesAbilityToSpend(uint256 balance, uint256 excessive) public {
        balance = bound(balance, 1, SUPPLY);
        excessive = bound(excessive, balance + 1, type(uint256).max - 1);
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, excessive));

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, excessive)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, excessive);
        assertEq(token.allowance(alice, spender), excessive);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, balance));
        assertEq(token.allowance(alice, spender), excessive - balance);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), balance);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_refillingAnEmptiedHolderDoesNotRestoreSpentAllowance() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(alice, spender), 0);

        vm.prank(bob);
        assertTrue(token.transfer(alice, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, spender), 0);

        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.allowance(alice, spender), 0);
    }

    function testFuzz_approvedSelfTransferStillRequiresBalance(uint256 balance, bool infinite) public {
        balance = bound(balance, 0, SUPPLY);
        uint256 value = balance + 1;
        uint256 allowed = infinite ? type(uint256).max : value;
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, allowed));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, value));
        vm.prank(spender);
        token.transferFrom(alice, alice, value);
        assertEq(token.allowance(alice, spender), allowed);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maxUintTransferFailsWithBalanceErrorAndPreservesInfiniteApproval() public {
        uint256 value = type(uint256).max;
        assertTrue(token.approve(spender, value));
        bytes memory errorData =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, value);
        vm.expectRevert(errorData);
        token.transfer(alice, value);
        vm.expectRevert(errorData);
        vm.prank(spender);
        token.transferFrom(address(this), alice, value);

        assertEq(token.allowance(address(this), spender), value);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroAmountDoesNotBypassInvalidAddressChecks() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(alice);
        token.transfer(address(0), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(alice, address(0), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(alice);
        token.approve(address(0), 0);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.allowance(alice, address(0)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_tokensSentToTheTokenContractRemainInSupply() public {
        assertTrue(token.transfer(address(token), 1));
        assertTrue(token.approve(spender, SUPPLY - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(token), SUPPLY - 1));
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(token), alice, 1);
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_ownerCanUseTransferFromOnlyWithSelfApproval() public {
        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function testFuzz_allowanceCannotBeUsedAgainstAnotherOwner(uint256 value) public {
        value = bound(value, 1, SUPPLY);
        assertTrue(token.approve(spender, value));
        assertTrue(token.transfer(alice, value));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, value));
        vm.prank(spender);
        token.transferFrom(alice, bob, value);
        assertEq(token.allowance(address(this), spender), value);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), value);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - value);
    }

    function testFuzz_zeroDelegatedTransferPreservesAnyAllowance(uint256 allowed) public {
        vm.prank(alice);
        assertTrue(token.approve(spender, allowed));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), allowed);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
