// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { LibDiamond } from "../libraries/LibDiamond.sol";
import { IGovernanceFacet } from "../interfaces/IGovernanceFacet.sol";

/// @title GovernanceFacet
/// @notice Timelock-gated mutators for diamond-level governance state that
///         lives outside the cut map: selector pause, freeze switch, and
///         selector version metadata. Every external function is callable
///         only by the diamond's ProxyTimelock.
///
///         Kept separate from DiamondCutFacet so the cut interface stays
///         pure EIP-2535 and this facet can be audited in isolation.
contract GovernanceFacet is IGovernanceFacet {
    error ArrayLengthMismatch();

    // --------------------------------------------
    //  Pause / unpause (immediate)
    // --------------------------------------------

    function pauseSelectors(bytes4[] calldata selectors) external override {
        LibDiamond.enforceIsProxyTimelock();
        uint256 len = selectors.length;
        for (uint256 i; i < len; ) {
            LibDiamond.setSelectorPaused(selectors[i], true);
            unchecked { ++i; }
        }
    }

    function unpauseSelectors(bytes4[] calldata selectors) external override {
        LibDiamond.enforceIsProxyTimelock();
        uint256 len = selectors.length;
        for (uint256 i; i < len; ) {
            LibDiamond.setSelectorPaused(selectors[i], false);
            unchecked { ++i; }
        }
    }

    // --------------------------------------------
    //  Freeze (one-way)
    // --------------------------------------------

    /// @notice Permanently disable all future cuts. Irreversible. After
    ///         freezing, the diamond becomes an immutable contract system —
    ///         pause/unpause and metadata changes remain possible, but no
    ///         new selectors can be added.
    function freeze() external override {
        LibDiamond.enforceIsProxyTimelock();
        LibDiamond.freezeDiamond();
    }

    // --------------------------------------------
    //  Selector metadata
    // --------------------------------------------

    function setSelectorMeta(
        bytes4 selector,
        bytes32 family,
        uint32 version
    ) external override {
        LibDiamond.enforceIsProxyTimelock();
        LibDiamond.setSelectorMeta(selector, family, version);
    }

    function setSelectorMetaBatch(
        bytes4[] calldata selectors,
        bytes32[] calldata families,
        uint32[] calldata versions
    ) external override {
        LibDiamond.enforceIsProxyTimelock();
        uint256 len = selectors.length;
        if (families.length != len || versions.length != len) revert ArrayLengthMismatch();
        for (uint256 i; i < len; ) {
            LibDiamond.setSelectorMeta(selectors[i], families[i], versions[i]);
            unchecked { ++i; }
        }
    }

    function setSelectorDeprecated(bytes4 selector, bool deprecated) external override {
        LibDiamond.enforceIsProxyTimelock();
        LibDiamond.setSelectorDeprecated(selector, deprecated);
    }
}
