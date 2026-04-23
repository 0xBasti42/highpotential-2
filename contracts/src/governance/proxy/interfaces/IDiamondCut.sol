// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

/*//////////////////////////////////////////////////////////////
//                        IDiamondCut
//------------------------------------------------------------
//  EIP-2535 cut interface. The enum retains the canonical three
//  actions (Add / Replace / Remove) for tooling compatibility, but
//  this HighPotential deployment enforces *append-only* semantics:
//  `diamondCut` calls whose FacetCut entries contain Replace or
//  Remove will revert with `AppendOnly(...)` in LibDiamond. The
//  enum values are preserved so that explorers, indexers, and ABI
//  consumers (Louper, Etherscan, wagmi generators) continue to
//  recognise the contract as EIP-2535 compliant.
//////////////////////////////////////////////////////////////*/

interface IDiamondCut {
    enum FacetCutAction { Add, Replace, Remove }
    // Add = 0, Replace = 1, Remove = 2
    // Only Add is accepted by this diamond; Replace and Remove revert.

    struct FacetCut {
        address facetAddress;
        FacetCutAction action;
        bytes4[] functionSelectors;
    }

    /// @notice Add a set of functions to the diamond and optionally run an
    ///         initialisation function via delegatecall.
    /// @param _diamondCut Array of FacetCut entries. Every entry must have
    ///        `action == Add` — Replace and Remove are rejected at runtime.
    /// @param _init Optional initialisation contract (zero address to skip).
    ///        Each init address may be used at most once across the diamond's
    ///        lifetime.
    /// @param _calldata ABI-encoded call data to delegatecall into `_init`.
    ///        Must be empty iff `_init` is the zero address.
    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external;

    event DiamondCut(FacetCut[] _diamondCut, address _init, bytes _calldata);
}
