// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IFactory {
   function getPair(address tokenA, address tokenB) external pure returns (address pair);
   function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IRouter {
   function factory() external pure returns (address);
   function WETH() external pure returns (address);
   function addLiquidityETH(address token, uint amountTokenDesired, uint amountTokenMin, uint amountETHMin, address to, uint deadline) external payable returns (uint amountToken, uint amountETH, uint liquidity);
   function swapExactTokensForETHSupportingFeeOnTransferTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external;
   function swapExactETHForTokensSupportingFeeOnTransferTokens(uint amountOutMin, address[] calldata path, address to, uint deadline) external payable;
   function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external payable;
   function addLiquidity(address tokenA, address tokenB, uint amountADesired, uint amountBDesired, uint amountAMin, uint amountBMin, address to, uint deadline) external returns (uint amountA, uint amountB, uint liquidity);
}
