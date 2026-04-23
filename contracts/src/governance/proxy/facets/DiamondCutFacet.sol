// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { IDiamondCut } from "../interfaces/IDiamondCut.sol";
import { LibDiamond } from "../libraries/LibDiamond.sol";

/// @title DiamondCutFacet
/// @notice Sole entry point for modifying the diamond's selector map. Only
///         accepts `Add` actions (append-only), gated on the VersionedProxyAdmin
///         authority. Reverts if the diamond has been frozen.
contract DiamondCutFacet is IDiamondCut {
    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external override {
        LibDiamond.enforceIsVersionedProxyAdmin();
        LibDiamond.diamondCut(_diamondCut, _init, _calldata);
    }
}
