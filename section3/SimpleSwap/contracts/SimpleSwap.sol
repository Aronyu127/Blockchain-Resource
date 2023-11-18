// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ISimpleSwap } from "./interface/ISimpleSwap.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract SimpleSwap is ISimpleSwap, ERC20("SimpleSwap", "SS") {
    using SafeMath for uint256;

    address tokenA;
    address tokenB;
    uint256 private reserveA;
    uint256 private reserveB;

    event Sync(uint256 reserveA, uint256 reserveB);
    event Mint(address indexed sender, uint amountA, uint amountB);
    event Burn(address indexed sender, uint amountA, uint amountB, address to);

    constructor(address _tokenA, address _tokenB) {
        require(isContract(_tokenA), "SimpleSwap: TOKENA_IS_NOT_CONTRACT");
        require(isContract(_tokenB), "SimpleSwap: TOKENB_IS_NOT_CONTRACT");

        (tokenA, tokenB) = sortTokens(_tokenA, _tokenB);
    }

    function isContract(address _address) public view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_address)
        }
        return (size > 0);
    }

    function sortTokens(address _tokenA, address _tokenB) internal pure returns (address token0, address token1) {
        require(_tokenA != _tokenB, "SimpleSwap: TOKENA_TOKENB_IDENTICAL_ADDRESS");
        (token0, token1) = _tokenA < _tokenB ? (_tokenA, _tokenB) : (_tokenB, _tokenA);
        require(token0 != address(0), "SimpleSwap: ZERO_ADDRESS");
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256 amountOut) {
        require(tokenIn == tokenA || tokenIn == tokenB, "SimpleSwap: INVALID_TOKEN_IN");
        require(tokenOut == tokenA || tokenOut == tokenB, "SimpleSwap: INVALID_TOKEN_OUT");
        require(tokenOut != tokenIn, "SimpleSwap: IDENTICAL_ADDRESS");
        require(amountIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");
        (uint256 reserveIn, uint256 reserveOut) = tokenIn == tokenA ? (reserveA, reserveB) : (reserveB, reserveA);
        require(reserveIn > 0 && reserveOut > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY");
        uint256 numerator = amountIn.mul(reserveOut);
        uint256 denominator = reserveIn.add(amountIn);
        amountOut = numerator / denominator;
        require(amountOut > 0, "SimpleSwap: INSUFFICIENT_OUTPUT_AMOUNT");
        if (tokenIn == tokenA) {
            reserveA = reserveA.add(amountIn);
            reserveB = reserveB.sub(amountOut);
            ERC20(tokenA).transferFrom(msg.sender, address(this), amountIn);
            ERC20(tokenB).transfer(msg.sender, amountOut);
        } else {
            reserveB = reserveB.add(amountIn);
            reserveA = reserveA.sub(amountOut);
            ERC20(tokenB).transferFrom(msg.sender, address(this), amountIn);
            ERC20(tokenA).transfer(msg.sender, amountOut);
        }
        emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    function _addLiquidity(
        uint256 amountADesired,
        uint256 amountBDesired
    ) internal view returns (uint256 amountA, uint256 amountB) {
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function addLiquidity(
        uint256 amountADesired,
        uint256 amountBDesired
    ) external override returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        require(amountADesired > 0 && amountBDesired > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");
        (amountA, amountB) = _addLiquidity(amountADesired, amountBDesired);
        ERC20(tokenA).transferFrom(msg.sender, address(this), amountA);
        ERC20(tokenB).transferFrom(msg.sender, address(this), amountB);
        liquidity = mint(msg.sender);
        emit AddLiquidity(msg.sender, amountA, amountB, liquidity);
    }

    function removeLiquidity(uint256 liquidity) external returns (uint256 amountA, uint256 amountB) {
        this.transferFrom(msg.sender, address(this), liquidity);
        (amountA, amountB) = burn(msg.sender);
        emit RemoveLiquidity(msg.sender, amountA, amountB, liquidity);
    }

    function getReserves() external view override returns (uint256 _reserveA, uint256 _reserveB) {
        _reserveA = reserveA;
        _reserveB = reserveB;
    }

    function getTokenA() external view override returns (address _tokenA) {
        _tokenA = tokenA;
    }

    function getTokenB() external view override returns (address _tokenB) {
        _tokenB = tokenB;
    }

    function mint(address to) public returns (uint liquidity) {
        uint balanceA = ERC20(tokenA).balanceOf(address(this));
        uint balanceB = ERC20(tokenB).balanceOf(address(this));
        uint amountA = balanceA.sub(reserveA);
        uint amountB = balanceB.sub(reserveB);

        uint256 totalSupply = totalSupply();
        if (totalSupply == 0) {
            liquidity = Math.sqrt(amountA.mul(amountB));
        } else {
            liquidity = Math.min(amountA.mul(totalSupply) / reserveA, amountB.mul(totalSupply) / reserveB);
        }
        require(liquidity > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        _update(balanceA, balanceB);
        emit Mint(msg.sender, amountA, amountB);
    }

    function burn(address to) internal returns (uint256 amountA, uint256 amountB) {
        uint256 balanceA = ERC20(tokenA).balanceOf(address(this));
        uint256 balanceB = ERC20(tokenB).balanceOf(address(this));
        uint256 liquidity = balanceOf(address(this));

        uint256 totalSupply = totalSupply();
        amountA = liquidity.mul(balanceA) / totalSupply; // using balances ensures pro-rata distribution
        amountB = liquidity.mul(balanceB) / totalSupply; // using balances ensures pro-rata distribution
        require(amountA > 0 && amountB > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_BURNED");
        _burn(address(this), liquidity);
        ERC20(tokenA).transfer(to, amountA);
        ERC20(tokenB).transfer(to, amountB);
        balanceA = ERC20(tokenA).balanceOf(address(this));
        balanceB = ERC20(tokenB).balanceOf(address(this));

        _update(balanceA, balanceB);
        emit Burn(msg.sender, amountA, amountB, to);
    }

    function _update(uint balanceA, uint balanceB) private {
        reserveA = uint256(balanceA);
        reserveB = uint256(balanceB);
        emit Sync(reserveA, reserveB);
    }

    function quote(uint amountA, uint _reserveA, uint _reserveB) internal pure returns (uint amountB) {
        require(amountA > 0, "INSUFFICIENT_AMOUNT");
        require(_reserveA > 0 && _reserveB > 0, "INSUFFICIENT_LIQUIDITY");
        amountB = amountA.mul(_reserveB) / _reserveA;
    }
}
