// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./dependencies/Ownable.sol";
import "./interfaces/IZap.sol";
import "./interfaces/IZapHandler.sol";

// reentrancy guards required? unlikely since it just cancels the previous zapping?
contract Zap is Ownable, IZap {
    using SafeERC20 for IERC20;
    
    // The zap handler implementation takes care of 
    IZapHandler public implementation;
    
    address public from = address(1); // from reverts to address(1) to save gas.
    IERC20 public pendingToken;
    uint256 public remaining = 1; // we set remaining to 1 as a gas optimization, terrible for readability but it iz what it iz

    event ImplementationChanged(IZapHandler indexed oldImplementation, IZapHandler indexed newImplementation);

    // to parameter? yes.
    function swapERC20(IERC20 fromToken, IERC20 toToken, address to, uint256 amount, uint256 minReceived) external override returns (uint256 received) {
        from = msg.sender;
        pendingToken = fromToken;
        remaining = amount + 1;

        uint256 beforeBal = toToken.balanceOf(to);
        implementation.convertERC20(fromToken, toToken, to, amount);
        from = address(1);

        uint256 receivedTokens = toToken.balanceOf(to) - beforeBal; 

        require(receivedTokens >= minReceived, "!minimum not received");
        // Unfortunately no event to save gas.
        return receivedTokens;
    }
    
    function swapERC20Fast(IERC20 fromToken, IERC20 toToken, uint256 amount) external override {
        from = msg.sender;
        pendingToken = fromToken;
        remaining = amount + 1;

        implementation.convertERC20(fromToken, toToken, msg.sender, amount);
        from = address(1);
    }
    
    function pullTo(address to) external override {
        require(msg.sender == address(implementation), "!implementation");
        uint256 amount = remaining - 1;
        remaining = 1; // Safeguard that the implementation cannot overdraft
        pendingToken.safeTransferFrom(from, to, amount);
    }

    function pullAmountTo(address to, uint256 amount) external override {
        require(msg.sender == address(implementation), "!implementation");
        require(remaining >= amount + 1, "!overdraft");
        unchecked {
            remaining -= amount; // Safeguard that the implementation cannot overdraft
        }

        pendingToken.safeTransferFrom(from, to, amount);
    }

    function setImplementation(IZapHandler _implementation) external onlyOwner {
        IZapHandler oldImplementation = implementation;
        implementation = _implementation;

        emit ImplementationChanged(oldImplementation, _implementation);

    }
}