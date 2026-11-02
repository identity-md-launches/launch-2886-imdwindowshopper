// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IMDwindowshopper} from "../src/IMDwindowshopper.sol";

/// @dev Test-only factory. No deployment addresses in this suite represent live contracts.
contract TokenFactoryHarness {
    function deploy(bytes32 salt) external returns (IMDwindowshopper) {
        return new IMDwindowshopper{salt: salt}();
    }
}

contract IMDwindowshopperTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    IMDwindowshopper internal token;
    address internal alice;
    address internal bob;
    address internal spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        token = new IMDwindowshopper();
    }

    function test_metadataAndEntireSupply() public view {
        assertEq(token.name(), "IMDwindowshopper");
        assertEq(token.symbol(), "WWW");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_constructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        IMDwindowshopper fresh = new IMDwindowshopper();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_create2FactoryGetsEntireSupply() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        bytes32 salt = keccak256("test launch");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), address(factory), salt, keccak256(type(IMDwindowshopper).creationCode)
                        )
                    )
                )
            )
        );
        vm.prank(alice, bob);
        IMDwindowshopper launched = factory.deploy(salt);
        assertEq(address(launched), predicted);
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(alice), 0);
        assertEq(launched.balanceOf(bob), 0);
        assertEq(launched.balanceOf(address(this)), 0);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function testFuzz_constructorMintsToImmediateDeployer(address deployer) public {
        vm.assume(deployer != address(0));
        vm.prank(deployer);
        IMDwindowshopper fresh = new IMDwindowshopper();
        assertEq(fresh.totalSupply(), SUPPLY);
        assertEq(fresh.balanceOf(deployer), SUPPLY);
    }

    function test_transferWholeSupplyAndBack() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, SUPPLY);
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_transferOneBaseUnit() public {
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_revertWhenSelfTransferExceedsBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(address(this), SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testFuzz_transferConservesSupply(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_revertWhenTransferExceedsBalance(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(alice, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_revertWhenEmptyAccountTransfersPositiveAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(bob), 0);
    }

    function testFuzz_revertWhenTransferRecipientIsZero(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approveEmitsEventAndCanBeReplacedAndRevoked() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 100);
        assertTrue(token.approve(spender, 100));
        assertEq(token.allowance(address(this), spender), 100);
        assertTrue(token.approve(spender, 25));
        assertEq(token.allowance(address(this), spender), 25);
        assertTrue(token.approve(spender, 0));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_approvalDoesNotRequireBalance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, SUPPLY));
        assertEq(token.allowance(alice, spender), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_revertWhenApprovingZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_transferFromSpendsFiniteAllowanceAndEmitsTransfer() public {
        assertTrue(token.approve(spender, 100));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), bob, 40);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 40));
        assertEq(token.allowance(address(this), spender), 60);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 60));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(bob), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY - 100);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromConservesSupplyAndAllowance(uint256 allowance_, uint256 amount) public {
        allowance_ = bound(allowance_, 0, SUPPLY);
        amount = bound(amount, 0, allowance_);
        assertTrue(token.approve(spender, allowance_));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, amount));
        assertEq(token.allowance(address(this), spender), allowance_ - amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteAllowanceRemainsUnchanged() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY - 1);
        assertEq(token.balanceOf(bob), 1);
    }

    function test_zeroTransferFromNeedsNoAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferFromSelfConsumesAllowanceWithoutMovingBalance() public {
        assertTrue(token.approve(spender, 20));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 20));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_revertWhenOwnerUsesTransferFromWithoutSelfApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), bob, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_revertWhenDifferentSpenderUsesAllowance() public {
        assertTrue(token.approve(spender, 100));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    function testFuzz_revertWhenAllowanceIsInsufficient(uint256 allowance_) public {
        allowance_ = bound(allowance_, 0, SUPPLY - 1);
        assertTrue(token.approve(spender, allowance_));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance_, allowance_ + 1
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), bob, allowance_ + 1);
        assertEq(token.allowance(address(this), spender), allowance_);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_revertWhenApprovedTransferExceedsBalanceRollsBackAllowance() public {
        assertTrue(token.transfer(alice, 10));
        vm.prank(alice);
        assertTrue(token.approve(spender, 11));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10, 11));
        vm.prank(spender);
        token.transferFrom(alice, bob, 11);
        assertEq(token.allowance(alice, spender), 11);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_revertWhenApprovedRecipientIsZeroRollsBackAllowance() public {
        assertTrue(token.approve(spender, 50));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 50);
        assertEq(token.allowance(address(this), spender), 50);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_revertWhenTransferFromZeroAddress() public {
        vm.expectRevert();
        vm.prank(spender);
        token.transferFrom(address(0), bob, 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_deployerCannotSpendHolderBalanceWithoutApproval() public {
        assertTrue(token.transfer(alice, 100));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 100));
        token.transferFrom(alice, bob, 100);
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_noMintBurnAdminOrUpgradeEntryPoints() public {
        assertTrue(token.transfer(alice, 100));
        string[16] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "initialize(address)",
            "setMinter(address)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "pause()",
            "blacklist(address)",
            "freeze(address)",
            "seize(address)",
            "transferOwnership(address)",
            "setOwner(address)",
            "upgradeTo(address)",
            "owner()"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], alice, 100);
            (bool fromDeployer,) = address(token).call(data);
            assertFalse(fromDeployer, signatures[i]);
            vm.prank(bob);
            (bool fromStranger,) = address(token).call(data);
            assertFalse(fromStranger, signatures[i]);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(alice), 100);
        }
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100));
        assertEq(token.balanceOf(bob), 100);
    }

    function test_factoryDistributionAndTradingTransfersArriveWhole() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        IMDwindowshopper launched = factory.deploy(keccak256("distribution test"));
        address distributor = makeAddr("test distributor");
        address pool = makeAddr("test pool balance holder");
        address remainder = makeAddr("test remainder recipient");
        uint256 swarmShare = SUPPLY / 10;
        uint256 poolShare = SUPPLY * 8 / 10;
        vm.startPrank(address(factory));
        assertTrue(launched.transfer(distributor, swarmShare));
        assertTrue(launched.transfer(pool, poolShare));
        assertTrue(launched.transfer(remainder, SUPPLY - swarmShare - poolShare));
        vm.stopPrank();
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(distributor), swarmShare);
        assertEq(launched.balanceOf(pool), poolShare);
        assertEq(launched.balanceOf(remainder), SUPPLY / 10);
        vm.prank(distributor);
        assertTrue(launched.transfer(alice, swarmShare));
        assertEq(launched.balanceOf(alice), swarmShare);
        assertEq(launched.balanceOf(distributor), 0);
        // Exercises exact token movements, not Uniswap price/liquidity calculations.
        vm.prank(pool);
        assertTrue(launched.transfer(bob, 123e18));
        assertEq(launched.balanceOf(bob), 123e18);
        vm.prank(bob);
        assertTrue(launched.transfer(pool, 123e18));
        assertEq(launched.balanceOf(bob), 0);
        assertEq(launched.balanceOf(pool), poolShare);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_plainEtherAndUnknownCallsRevert() public {
        vm.deal(address(this), 1 ether);
        (bool acceptsEther,) = address(token).call{value: 1 ether}("");
        assertFalse(acceptsEther);
        (bool acceptsUnknownCall,) = address(token).call(hex"deadbeef");
        assertFalse(acceptsUnknownCall);
        assertEq(address(token).balance, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
