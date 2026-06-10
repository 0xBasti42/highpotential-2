// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

/// @title IDepositConverter
/// @notice Swap leg of the deposit router: converts an allowlisted ERC-20 into native ETH.
/// @dev Implementations (e.g. a Uniswap V4 converter with admin-configured multi-hop routes such as
///      TGBP -> USDC -> ETH) pull `amount` of `token` from the caller (pre-approved), execute the swap,
///      and send the resulting native ETH back to the caller. The router independently verifies the
///      received amount against `minEthOut`, so converters are swappable via the DEPOSIT_CONVERTER
///      AddressProvider key without being fully trusted for output accounting.
interface IDepositConverter {
    function convertToEth(address token, uint256 amount, uint256 minEthOut) external returns (uint256 ethOut);
}
