// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IMDwindowshopper} from "../src/IMDwindowshopper.sol";

/// @dev Closed set of holders with an independent ledger for randomized transaction sequences.
contract TokenHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    IMDwindowshopper public immutable token;
    address[4] public actors;
    address internal immutable outsider;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(IMDwindowshopper token_) {
        token = token_;
        actors = [makeAddr("holder0"), makeAddr("holder1"), makeAddr("holder2"), makeAddr("holder3")];
        outsider = makeAddr("unapproved outsider");
        expectedBalance[actors[0]] = SUPPLY;
    }

    function move(uint256 fromSeed, uint256 toSeed, uint256 valueSeed) public {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 value = bound(valueSeed, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, value));
        expectedBalance[from] -= value;
        expectedBalance[to] += value;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 value) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, value));
        expectedAllowance[owner][spender] = value;
    }

    /// @dev Make revocation and the finite/infinite boundary routine parts of random sequences.
    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint256 mode) public {
        uint256[5] memory values = [uint256(0), 1, SUPPLY, type(uint256).max - 1, type(uint256).max];
        approve(ownerSeed, spenderSeed, values[mode % values.length]);
    }

    function spend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 valueSeed) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 maximum = expectedBalance[owner] < allowed ? expectedBalance[owner] : allowed;
        uint256 value = bound(valueSeed, 0, maximum);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, value));
        expectedBalance[owner] -= value;
        expectedBalance[to] += value;
        if (allowed != type(uint256).max) {
            expectedAllowance[owner][spender] -= value;
        }
    }

    function rejectExcessTransfer(uint256 fromSeed, uint256 toSeed) public {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, balance + 1)
        );
        vm.prank(from);
        token.transfer(to, balance + 1);
    }

    function rejectUnapprovedSpend(uint256 ownerSeed, uint256 toSeed) public {
        address owner = actors[ownerSeed % actors.length];
        address to = actors[toSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, outsider, 0, 1));
        vm.prank(outsider);
        token.transferFrom(owner, to, 1);
    }

    /// @dev A failed transfer must roll back an allowance debit, even after arbitrary prior activity.
    function rejectApprovedOverBalance(uint256 ownerSeed, uint256 spenderSeed, bool infinite) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        uint256 value = balance + 1;
        uint256 allowed = infinite ? type(uint256).max : value;
        approve(ownerSeed, spenderSeed, allowed);
        assertEq(token.allowance(owner, spender), allowed);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, value));
        vm.prank(spender);
        token.transferFrom(owner, spender, value);
        assertEq(token.allowance(owner, spender), allowed);
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 valueSeed) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 value = bound(valueSeed, 0, expectedBalance[owner]);
        approve(ownerSeed, spenderSeed, value);
        assertEq(token.allowance(owner, spender), value);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(owner, address(0), value);
        assertEq(token.allowance(owner, spender), value);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(owner);
        token.transfer(address(0), value);
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 value) public {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), value);
        assertEq(token.allowance(owner, address(0)), 0);
    }

    /// @dev Always move a positive full balance; check each leg so two bad deltas cannot cancel.
    function fullBalanceRoundTrip(uint256 fromSeed, uint256 toSeed) public {
        uint256 fromIndex = _fundedActorIndex(fromSeed);
        uint256 toIndex = (fromIndex + 1 + toSeed % (actors.length - 1)) % actors.length;
        address from = actors[fromIndex];
        address to = actors[toIndex];
        uint256 value = expectedBalance[from];
        uint256 toBefore = expectedBalance[to];

        move(fromIndex, toIndex, value);
        assertEq(token.balanceOf(from), 0);
        assertEq(token.balanceOf(to), toBefore + value);
        move(toIndex, fromIndex, value);
        assertEq(token.balanceOf(from), value);
        assertEq(token.balanceOf(to), toBefore);
    }

    /// @dev A self-transfer preserves balance but still needs and spends a finite allowance.
    function selfSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 valueSeed, bool infinite) public {
        uint256 ownerIndex = _fundedActorIndex(ownerSeed);
        address owner = actors[ownerIndex];
        address spender = actors[spenderSeed % actors.length];
        uint256 beforeBalance = expectedBalance[owner];
        uint256 value = bound(valueSeed, 1, beforeBalance);
        approve(ownerIndex, spenderSeed, infinite ? type(uint256).max : value);
        spend(ownerIndex, spenderSeed, ownerIndex, value);
        assertEq(token.balanceOf(owner), beforeBalance);
        assertEq(token.allowance(owner, spender), infinite ? type(uint256).max : 0);
    }

    function _fundedActorIndex(uint256 seed) internal view returns (uint256 index) {
        index = seed % actors.length;
        for (uint256 i; i < actors.length; ++i) {
            if (expectedBalance[actors[index]] > 0) return index;
            index = (index + 1) % actors.length;
        }
        revert("fixed supply must have a holder");
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract IMDwindowshopperInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    IMDwindowshopper internal token;
    TokenHandler internal handler;

    function setUp() public {
        token = new IMDwindowshopper();
        handler = new TokenHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));

        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = TokenHandler.move.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.spend.selector;
        selectors[3] = TokenHandler.rejectExcessTransfer.selector;
        selectors[4] = TokenHandler.rejectUnapprovedSpend.selector;
        selectors[5] = TokenHandler.approveBoundary.selector;
        selectors[6] = TokenHandler.rejectApprovedOverBalance.selector;
        selectors[7] = TokenHandler.rejectZeroRecipient.selector;
        selectors[8] = TokenHandler.rejectZeroSpender.selector;
        selectors[9] = TokenHandler.fullBalanceRoundTrip.selector;
        selectors[10] = TokenHandler.selfSpend.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_balancesAllowancesAndSupplyMatchIndependentLedger() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            uint256 balance = token.balanceOf(owner);
            assertEq(balance, handler.expectedBalance(owner));
            sum += balance;
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }
}
