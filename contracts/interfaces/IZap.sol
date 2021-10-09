// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IZap {

    function swapERC20(IERC20 fromToken, IERC20 toToken, address to, uint256 amount, uint256 minReceived) external returns (uint256 received);
    function swapERC20Fast(IERC20 fromToken, IERC20 toToken, uint256 amount) external;

    function pullTo(address to) external;
    function pullAmountTo(address to, uint256 amount) external;
}