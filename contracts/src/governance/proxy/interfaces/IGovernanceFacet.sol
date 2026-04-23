// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

/// @title IGovernanceFacet
/// @notice External surface of the HighPotential-specific GovernanceFacet.
///         Callable only by the ProxyTimelock registered on the diamond.
///         Held in a dedicated interface so other contracts (LibDiamond's
///         infrastructure whitelist, ProxyTimelock's cross-contract calls)
///         can reference its selectors without importing the implementation.
interface IGovernanceFacet {
    function pauseSelectors(bytes4[] calldata selectors) external;
    function unpauseSelectors(bytes4[] calldata selectors) external;
    function freeze() external;
    function setSelectorMeta(bytes4 selector, bytes32 family, uint32 version) external;
    function setSelectorMetaBatch(
        bytes4[] calldata selectors,
        bytes32[] calldata families,
        uint32[] calldata versions
    ) external;
    function setSelectorDeprecated(bytes4 selector, bool deprecated) external;
}
