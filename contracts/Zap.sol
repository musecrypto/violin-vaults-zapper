// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./dependencies/Ownable.sol";
import "./interfaces/IZap.sol";
import "./interfaces/IZapHandler.sol";

/// @notice The Zap contract is an interface that allows other contracts to swap a token for another token without having to directly interact with verbose AMMs directly.
/// @notice It furthermore allows to zap to and from an LP pair within a single transaction.
/// @dev All though the underlying implementation is upgradeable, the Zap contract provides a safe wrapper that the implementation can never access approved funds.
contract Zap is Ownable, IZap {
    using SafeERC20 for IERC20;
    
    /// @dev The implementation that actually executes the swap orders
    IZapHandler public implementation;

    /// @dev Temporary variables that are set at the beginning of a swap and unset at the end of a swap.
    /// @dev This is necessary because the contract employs a pull hook flow to reduce the impact of transfer-tax tokens.
    /// @dev `from` and `remaining` have their zero variable moved to value 1, this is because EVMs charge a high cost for moving a variable away from zero.
    /// @dev Internally, remaining will always be corrected with a -1 factor.
    address public from = address(1);
    IERC20 public pendingToken;
    uint256 public remaining = 1;

    event ImplementationChanged(IZapHandler indexed oldImplementation, IZapHandler indexed newImplementation);
    
    /**
    * @notice Swap `amount` of `fromToken` to `toToken` and send them to the `to` address.
    * @notice The `fromToken` and `toToken` arguments can be AMM pairs.
    * @notice Reverts if the `to` address received less tokens than `minReceived`.
    * @notice Requires approval.
    * @param fromToken The token to take from `msg.sender` and exchange for `toToken`
    * @param toToken The token that will be bought and sent to the `to` address.
    * @param to The destination address to receive the `toToken`
    * @param amount The amount that the zapper should take from the `msg.sender` and swap
    * @param minReceived The minimum amount of `toToken` the `to` address should receive. Otherwise the transaction reverts.
    */
    function swapERC20(IERC20 fromToken, IERC20 toToken, address to, uint256 amount, uint256 minReceived) external override returns (uint256 received) {
        // Store transaction variables to be used by the implementation in the pullTo hooks.
        from = msg.sender;
        pendingToken = fromToken;
        remaining = amount + 1;

        uint256 beforeBal = toToken.balanceOf(to);
        
        // Call the implementation to execute the swap.
        implementation.convertERC20(fromToken, toToken, to, amount);

        // Unset the temporary variables. pendingToken and remaining do not need to be unset.
        from = address(1);

        // Validate that sufficient tokens were received within the `to` address.
        uint256 receivedTokens = toToken.balanceOf(to) - beforeBal; 
        require(receivedTokens >= minReceived, "!minimum not received");

        return receivedTokens;
    }
    

    /**
    * @notice Swap `amount` of `fromToken` to `toToken` and send them to the `msg.sender`.
    * @notice The `fromToken` and `toToken` arguments can be AMM pairs.
    * @notice Requires approval.
    * @param fromToken The token to take from `msg.sender` and exchange for `toToken`.
    * @param toToken The token that will be bought and sent to the `msg.sender`.
    * @param amount The amount that the zapper should take from the `msg.sender` and swap.
    */
    function swapERC20Fast(IERC20 fromToken, IERC20 toToken, uint256 amount) external override {
        // Store transaction variables to be used by the implementation in the pullTo hooks.
        from = msg.sender;
        pendingToken = fromToken;
        remaining = amount + 1;

        // Call the implementation to execute the swap.
        implementation.convertERC20(fromToken, toToken, msg.sender, amount);

        // Unset the temporary variables. pendingToken and remaining do not need to be unset.
        from = address(1);
    }
    
    /**
    * @notice When the implementation calls pullTo while in a swap, the remaining tokens of the `swap` amount will be sent from the swap `msg.sender` to the `to` address chosen by the implementation.
    * @notice This amount cannot exceed the amount set in the original swap transaction.
    * @notice Traditionally these funds would just be transferred to the implementation which then forwards them to the pairs.
    * @notice However, by using pull hooks, one avoids a transfer which is important for transfer-tax tokens.
    * @dev Can only be called by the implementation.
    * @param to The address to send all remaining tokens of the swap to. This is presumably the first AMM pair in the route.
    */
    function pullTo(address to) external override {
        require(msg.sender == address(implementation), "!implementation");
        uint256 amount = remaining - 1;
        remaining = 1;
        pendingToken.safeTransferFrom(from, to, amount);
    }

    /**
    * @notice When the implementation calls pullAmountTo while in a swap, `amount` tokens of the `swap` amount will be sent from the swap`msg.sender` to the `to` address chosen by the implementation.
    * @notice This amount cannot exceed the amount set in the original swap transaction.
    * @notice Traditionally these funds would just be transferred to the implementation which then forwards them to the pairs.
    * @notice However, by using pull hooks, one avoids a transfer which is important for transfer-tax tokens.
    * @dev Can only be called by the implementation.
    * @param to The address to send `amount` tokens of the swap to. This is presumably the first AMM pair in the route.
    * @param amount The amount of tokens to send to the `to` address, cannot exceed the remaining amount indicated by the swap `amount` parameter.
    */
    function pullAmountTo(address to, uint256 amount) external override {
        require(msg.sender == address(implementation), "!implementation");
        require(remaining >= amount + 1, "!overdraft");
        unchecked {
            remaining -= amount; // Safeguard that the implementation cannot overdraft
        }

        pendingToken.safeTransferFrom(from, to, amount);
    }

    /**
     * @notice Sets the underlying implementation that fulfills the swap orders.
     * @dev Can only be called by the contract owner.
     * @param _implementation The new implementation.
     */
    function setImplementation(IZapHandler _implementation) external override onlyOwner {
        IZapHandler oldImplementation = implementation;
        implementation = _implementation;

        emit ImplementationChanged(oldImplementation, _implementation);

    }
}