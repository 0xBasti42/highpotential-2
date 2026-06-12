// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

/// @title IAerodromeRouter
/// @notice Minimal surface of Aerodrome's classic (Solidly-lineage) Router used by the deposit converter.
/// @dev Base mainnet deployment: 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43 (registered under the
///      AERODROME_ROUTER AddressProvider key). `swapExactTokensForETH` requires the final hop's `to`
///      to be WETH; the Aerodrome router unwraps internally and sends native ETH to the recipient.
interface IAerodromeRouter {
    struct Route {
        address from;
        address to;
        /// @dev true = stableswap math (correlated pairs), false = constant-product (volatile pairs).
        bool stable;
        /// @dev Pool factory for this hop; address(0) selects Aerodrome's default factory.
        address factory;
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}
