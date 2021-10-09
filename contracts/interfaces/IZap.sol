// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IZapHandler.sol";

/// @notice The IZap interface allows contracts to swap a token for another token without having to directly interact with verbose AMMs directly.
/// @notice It furthermore allows to zap to and from an LP pair within a single transaction.
interface IZap {
    /**
    * @notice Swap `amount` of `fromToken` to `toToken` and send them to the `recipient`.
    * @notice The `fromToken` and `toToken` arguments can be AMM pairs.
    * @notice Reverts if the `recipient` received less tokens than `minReceived`.
    * @notice Requires approval.
    * @param fromToken The token to take from `msg.sender` and exchange for `toToken`.
    * @param toToken The token that will be bought and sent to the `recipient`.
    * @param recipient The destination address to receive the `toToken`.
    * @param amount The amount that the zapper should take from the `msg.sender` and swap.
    * @param minReceived The minimum amount of `toToken` the `recipient` should receive. Otherwise the transaction reverts.
    */
    function swapERC20(IERC20 fromToken, IERC20 toToken, address recipient, uint256 amount, uint256 minReceived) external returns (uint256 received);


    /**
    * @notice Swap `amount` of `fromToken` to `toToken` and send them to the `msg.sender`.
    * @notice The `fromToken` and `toToken` arguments can be AMM pairs.
    * @notice Requires approval.
    * @param fromToken The token to take from `msg.sender` and exchange for `toToken`.
    * @param toToken The token that will be bought and sent to the `msg.sender`.
    * @param amount The amount that the zapper should take from the `msg.sender` and swap.
    */
    function swapERC20Fast(IERC20 fromToken, IERC20 toToken, uint256 amount) external;

    /**
    * @notice When the implementation calls pullTo while in a swap, the remaining tokens of the `swap` amount will be sent from the swap `msg.sender` to the `to` address chosen by the implementation.
    * @notice This amount cannot exceed the amount set in the original swap transaction.
    * @notice Traditionally these funds would just be transferred to the implementation which then forwards them to the pairs.
    * @notice However, by using pull hooks, one avoids a transfer which is important for transfer-tax tokens.
    * @dev Can only be called by the implementation.
    * @param to The address to send all remaining tokens of the swap to. This is presumably the first AMM pair in the route.
    */
    function pullTo(address to) external;

    /**
    * @notice When the implementation calls pullAmountTo while in a swap, `amount` tokens of the `swap` amount will be sent from the swap`msg.sender` to the `to` address chosen by the implementation.
    * @notice This amount cannot exceed the amount set in the original swap transaction.
    * @notice Traditionally these funds would just be transferred to the implementation which then forwards them to the pairs.
    * @notice However, by using pull hooks, one avoids a transfer which is important for transfer-tax tokens.
    * @dev Can only be called by the implementation.
    * @param to The address to send `amount` tokens of the swap to. This is presumably the first AMM pair in the route.
    * @param amount The amount of tokens to send to the `to` address, cannot exceed the remaining amount indicated by the swap `amount` parameter.
    */
    function pullAmountTo(address to, uint256 amount) external;

    /**
     * @notice Sets the underlying implementation that fulfills the swap orders.
     * @dev Can only be called by the contract owner.
     * @param implementation The new implementation.
     */
    function setImplementation(IZapHandler implementation) external;
}