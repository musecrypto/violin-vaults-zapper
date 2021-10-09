// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

// v0.8.6 interface into the uniswap factory.
contract MockFactory is IUniswapV2Factory {
    function feeTo() external view override returns (address) {
        return address(0);
    }

    function feeToSetter() external view override returns (address) {
        return address(0);
    }

    function getPair(address tokenA, address tokenB)
        external
        view
        override
        returns (address pair)
    {
        return address(0);
    }

    function allPairs(uint256) external view override returns (address pair) {
        return address(0);
    }

    function allPairsLength() external view override returns (uint256) {
        return 0;
    }

    function createPair(address tokenA, address tokenB)
        external
        override
        returns (address pair)
    {
        return address(0);
    }

    function setFeeTo(address) external override {}

    function setFeeToSetter(address) external override {}
}
contract MockPair is IUniswapV2Pair {
    function name() external override pure returns (string memory){return "";}
    function symbol() external override pure returns (string memory){return "";}
    function decimals() external override pure returns (uint8) {return 0;}
    function totalSupply() external override view returns (uint){return 0;}
    function balanceOf(address owner) external override view returns (uint){return 0;}
    function allowance(address owner, address spender) external override view returns (uint){return 0;}

    function approve(address spender, uint value) external override returns (bool){return false;}
    function transfer(address to, uint value) external override returns (bool) {return false;}
    function transferFrom(address from, address to, uint value) external override returns (bool){return false;}

    function DOMAIN_SEPARATOR() external override view returns (bytes32){return "";}
    function PERMIT_TYPEHASH() external override pure returns (bytes32) {return "";}
    function nonces(address owner) external override view returns (uint){return 0;}

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s)external override {}


    function MINIMUM_LIQUIDITY() external override pure returns (uint){return 0;}
    function factory() external override view returns (address){return address(0);}
    function token0() external override view returns (address){}
    function token1() external override view returns (address){}
    function getReserves() external override view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast){}
    function price0CumulativeLast() external override view returns (uint){}
    function price1CumulativeLast() external override view returns (uint){}
    function kLast() external override view returns (uint){}

    function mint(address to) external override returns (uint liquidity){}
    function burn(address to) external override returns (uint amount0, uint amount1){}
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external override{}
    function skim(address to) external override{}
    function sync() external override{}

 
   function initialize(address, address) external override{}

}
