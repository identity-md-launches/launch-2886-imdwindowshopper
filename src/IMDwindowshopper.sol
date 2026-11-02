// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title IMDwindowshopper (WWW)
/// @notice Fixed-supply, 18-decimal ERC-20 with the entire supply minted to its deployer.
/// @dev The launch factory is msg.sender during launch. There are no post-deployment admin powers.
contract IMDwindowshopper is ERC20 {
    /// @notice One billion whole tokens, expressed in the token's 18-decimal base units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("IMDwindowshopper", "WWW") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
