// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

/// @notice User's preferred crypto asset. Resolves via `AddressProvider` keys: CBBTC / WETH / SETH.
/// @dev ETH maps to the canonical WETH9 address on Base (0x4200...0006); SETH is the HP stability wrapper.
enum DefaultCrypto {
    BTC,
    ETH,
    SETH
}

/// @notice User's preferred stablecoin. Resolves via `AddressProvider` keys: TGBP / USDC / EURC / USDS.
enum DefaultStablecoin {
    TGBP,
    USDC,
    EURC,
    USDS
}
