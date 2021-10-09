// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IZapHandler {
    function convertERC20(IERC20 fromToken, IERC20 toToken, address to, uint256 amount) external;
}