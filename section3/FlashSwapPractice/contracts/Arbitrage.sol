// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV2Pair } from "v2-core/interfaces/IUniswapV2Pair.sol";
import { IUniswapV2Callee } from "v2-core/interfaces/IUniswapV2Callee.sol";
import "forge-std/Test.sol";

// This is a practice contract for flash swap arbitrage
contract Arbitrage is IUniswapV2Callee, Ownable {
    struct CallbackData {
        address priceLowerPoolAddress;
        address priceHigherPoolAddress;
        uint256 repayUsdcAmount;
        address repayToken;
        uint256 borrowAmount;
        address borrowToken;
    }
    //
    // EXTERNAL NON-VIEW ONLY OWNER
    //

    function withdraw() external onlyOwner {
        (bool success, ) = msg.sender.call{ value: address(this).balance }("");
        require(success, "Withdraw failed");
    }

    function withdrawTokens(address token, uint256 amount) external onlyOwner {
        require(IERC20(token).transfer(msg.sender, amount), "Withdraw failed");
    }

    //
    // EXTERNAL NON-VIEW
    //

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external override {
        // TODO
        require(sender == address(this), "Sender must be this contract");
        require(amount0 > 0 || amount1 > 0, "Amount must be greater than 0");
        CallbackData memory callBackData = abi.decode(data, (CallbackData));

        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(callBackData.priceHigherPoolAddress).getReserves();
        uint256 usdcAmountOut = _getAmountOut(callBackData.borrowAmount, reserve0, reserve1);
        IERC20(callBackData.borrowToken).transfer(callBackData.priceHigherPoolAddress, callBackData.borrowAmount);
        IUniswapV2Pair(callBackData.priceHigherPoolAddress).swap(
            0,
            usdcAmountOut,
            address(this),
            ""
        );
        IERC20(callBackData.repayToken).transfer(callBackData.priceLowerPoolAddress, callBackData.repayUsdcAmount);        
    }

    // Method 1 is
    //  - borrow WETH from lower price pool
    //  - swap WETH for USDC in higher price pool
    //  - repay USDC to lower pool
    // Method 2 is
    //  - borrow USDC from higher price pool
    //  - swap USDC for WETH in lower pool
    //  - repay WETH to higher pool
    // for testing convenient, we implement the method 1 here
    function arbitrage(address priceLowerPool, address priceHigherPool, uint256 borrowETH) external {
        // TODO
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(priceLowerPool).getReserves();
        uint256 repayUsdcAmount = _getAmountIn(borrowETH, reserve1, reserve0);
        address repayToken = IUniswapV2Pair(priceLowerPool).token1();
        address borrowToken = IUniswapV2Pair(priceLowerPool).token0();
        CallbackData memory callBackData = CallbackData(priceLowerPool, priceHigherPool, repayUsdcAmount, repayToken, borrowETH, borrowToken);
        
        IUniswapV2Pair(priceLowerPool).swap(borrowETH, 0, address(this), abi.encode(callBackData));
    }

    //
    // INTERNAL PURE
    //

    // copy from UniswapV2Library
    function _getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = numerator / denominator + 1;
    }

    // copy from UniswapV2Library
    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }
}
