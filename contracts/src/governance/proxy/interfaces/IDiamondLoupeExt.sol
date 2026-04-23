// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { LibDiamond } from "../libraries/LibDiamond.sol";

/// @title IDiamondLoupeExt
/// @notice HighPotential-specific extensions to the EIP-2535 loupe interface.
///         Exposes the governance / provenance / metadata state that the
///         standard loupe does not cover. Clients that only speak EIP-2535
///         can ignore this interface entirely; HighPotential-aware tooling
///         uses it to inspect the version chain, pause state, and provenance.
interface IDiamondLoupeExt {
    /// @notice Authority currently permitted to perform cuts, pause, and
    ///         metadata changes on this diamond.
    function versionedProxyAdmin() external view returns (address);

    /// @notice Returns true once the diamond has been permanently frozen.
    function isFrozen() external view returns (bool);

    /// @notice Extcodehash recorded for a facet at registration time. Allows
    ///         trustless verification of facet provenance against audited
    ///         artefacts without re-tracing deployment transactions.
    function facetCodeHash(address facet) external view returns (bytes32);

    /// @notice Whether a specific selector is currently paused at the diamond
    ///         fallback.
    function selectorPaused(bytes4 selector) external view returns (bool);

    /// @notice Batch query for pause state across an array of selectors.
    function selectorsPaused(bytes4[] calldata selectors) external view returns (bool[] memory);

    /// @notice Version metadata for a selector, if any has been registered.
    function selectorMeta(bytes4 selector) external view returns (LibDiamond.SelectorMeta memory);

    /// @notice Current canonical (latest-version) selector for a family.
    ///         Returns bytes4(0) if the family has no registered selectors.
    function latestInFamily(bytes32 family) external view returns (bytes4);
}
