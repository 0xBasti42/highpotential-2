// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

/// @title IDepositConverter
/// @notice Swap leg of the deposit router: converts an allowlisted ERC-20 into native ETH.
/// @dev Implementations (e.g. an Aerodrome converter with admin-configured multi-hop routes such as
///      TGBP -> USDC -> ETH, or PSM-prefixed routes such as USDS -> USDC -> ETH) pull `amount` of
///      `token` from the caller (pre-approved), execute the conversion, and send the resulting native
///      ETH back to the caller. The router independently verifies the received amount against
///      `minEthOut`, so converters are swappable via the DEPOSIT_CONVERTER AddressProvider key
///      without being fully trusted for output accounting.
///
///      `isConvertible` doubles as the Swap-class allowlist: the router treats any token with an
///      enabled route as swappable, so the converter's route table is the single source of truth
///      and listing a new token never requires a router redeploy.
interface IDepositConverter {
    function convertToEth(address token, uint256 amount, uint256 minEthOut) external returns (uint256 ethOut);

    function isConvertible(address token) external view returns (bool);
}
