// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IZapHandler {

    /**
    * @notice Swap `amount` of `fromToken` to `toToken` and send them to the recipient.
    * @notice The `fromToken` and `toToken` arguments can be AMM pairs.
    * @notice Requires `msg.sender` to be a Zap instance.
    * @param fromToken The token to take from `msg.sender` and exchange for `toToken`
    * @param toToken The token that will be bought and sent to the recipient.
    * @param recipient The destination address to receive the `toToken`.
    * @param amount The amount that the zapper should take from the `msg.sender` and swap.
    */
    function convertERC20(IERC20 fromToken, IERC20 toToken, address recipient, uint256 amount) external;
}