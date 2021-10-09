// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IZap {

    function zapERC20(IERC20 fromToken, IERC20 toToken, uint256 amount, uint256 minReceived) external returns (uint256 received);

    function pullTo(address to) external;
    function pullAmountTo(address to, uint256 amount) external;
}