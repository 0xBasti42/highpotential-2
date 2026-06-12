// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

/// @title IPSM3
/// @notice Minimal surface of Spark's PSM3 (Peg Stability Module) used by the deposit converter for
///         assets whose canonical liquidity path is a 1:1 PSM conversion rather than a DEX pool
///         (e.g. USDS -> USDC on Base).
/// @dev Base mainnet deployment: 0x1601843c5E9bC251A3272907010AFa41Fa18347E (registered under the
///      PSM3 AddressProvider key). Signature verified against the on-chain ABI. Swaps are
///      slippage-free at the module's conversion rate; `amountOut` reflects decimal rescaling
///      (e.g. 18-decimal USDS -> 6-decimal USDC).
interface IPSM3 {
    function swapExactIn(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver,
        uint256 referralCode
    ) external returns (uint256 amountOut);

    function previewSwapExactIn(
        address assetIn,
        address assetOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut);
}
