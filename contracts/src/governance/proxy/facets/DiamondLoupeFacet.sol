// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { LibDiamond } from "../libraries/LibDiamond.sol";
import { IDiamondLoupe } from "../interfaces/IDiamondLoupe.sol";
import { IDiamondLoupeExt } from "../interfaces/IDiamondLoupeExt.sol";
import { IERC165 } from "../interfaces/IERC165.sol";

/// @title DiamondLoupeFacet
/// @notice Implements the four canonical EIP-2535 loupe functions plus the
///         HighPotential-specific `IDiamondLoupeExt` surface (pause state,
///         freeze flag, facet code-hash provenance, selector metadata, and
///         the proxy-timelock address).
///
///         The standard four functions (facets, facetFunctionSelectors,
///         facetAddresses) walk the selectors array and are intended for
///         off-chain use. `facetAddress(bytes4)` is the only one cheap
///         enough to call on-chain reliably.
contract DiamondLoupeFacet is IDiamondLoupe, IDiamondLoupeExt, IERC165 {
    // --------------------------------------------
    //  EIP-2535 standard loupe
    // --------------------------------------------

    function facets() external override view returns (Facet[] memory facets_) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256 selectorCount = ds.selectors.length;
        facets_ = new Facet[](selectorCount);
        uint8[] memory numFacetSelectors = new uint8[](selectorCount);
        uint256 numFacets;

        for (uint256 selectorIndex; selectorIndex < selectorCount; selectorIndex++) {
            bytes4 selector = ds.selectors[selectorIndex];
            address facetAddress_ = ds.facetAddressAndSelectorPosition[selector].facetAddress;
            bool continueLoop;

            for (uint256 facetIndex; facetIndex < numFacets; facetIndex++) {
                if (facets_[facetIndex].facetAddress == facetAddress_) {
                    facets_[facetIndex].functionSelectors[numFacetSelectors[facetIndex]] = selector;
                    require(numFacetSelectors[facetIndex] < 255);
                    numFacetSelectors[facetIndex]++;
                    continueLoop = true;
                    break;
                }
            }
            if (continueLoop) continue;

            facets_[numFacets].facetAddress = facetAddress_;
            facets_[numFacets].functionSelectors = new bytes4[](selectorCount);
            facets_[numFacets].functionSelectors[0] = selector;
            numFacetSelectors[numFacets] = 1;
            numFacets++;
        }
        for (uint256 facetIndex; facetIndex < numFacets; facetIndex++) {
            uint256 numSelectors = numFacetSelectors[facetIndex];
            bytes4[] memory selectors = facets_[facetIndex].functionSelectors;
            assembly { mstore(selectors, numSelectors) }
        }
        assembly { mstore(facets_, numFacets) }
    }

    function facetFunctionSelectors(address _facet)
        external
        override
        view
        returns (bytes4[] memory _facetFunctionSelectors)
    {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256 selectorCount = ds.selectors.length;
        uint256 numSelectors;
        _facetFunctionSelectors = new bytes4[](selectorCount);

        for (uint256 selectorIndex; selectorIndex < selectorCount; selectorIndex++) {
            bytes4 selector = ds.selectors[selectorIndex];
            address facetAddress_ = ds.facetAddressAndSelectorPosition[selector].facetAddress;
            if (_facet == facetAddress_) {
                _facetFunctionSelectors[numSelectors] = selector;
                numSelectors++;
            }
        }
        assembly { mstore(_facetFunctionSelectors, numSelectors) }
    }

    function facetAddresses() external override view returns (address[] memory facetAddresses_) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256 selectorCount = ds.selectors.length;
        facetAddresses_ = new address[](selectorCount);
        uint256 numFacets;

        for (uint256 selectorIndex; selectorIndex < selectorCount; selectorIndex++) {
            bytes4 selector = ds.selectors[selectorIndex];
            address facetAddress_ = ds.facetAddressAndSelectorPosition[selector].facetAddress;
            bool continueLoop;
            for (uint256 facetIndex; facetIndex < numFacets; facetIndex++) {
                if (facetAddress_ == facetAddresses_[facetIndex]) {
                    continueLoop = true;
                    break;
                }
            }
            if (continueLoop) continue;

            facetAddresses_[numFacets] = facetAddress_;
            numFacets++;
        }
        assembly { mstore(facetAddresses_, numFacets) }
    }

    function facetAddress(bytes4 _functionSelector)
        external
        override
        view
        returns (address facetAddress_)
    {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        facetAddress_ = ds.facetAddressAndSelectorPosition[_functionSelector].facetAddress;
    }

    // --------------------------------------------
    //  ERC-165
    // --------------------------------------------

    function supportsInterface(bytes4 _interfaceId) external override view returns (bool) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        return ds.supportedInterfaces[_interfaceId];
    }

    // --------------------------------------------
    //  HighPotential extended introspection
    // --------------------------------------------

    function proxyTimelock() external override view returns (address) {
        return LibDiamond.proxyTimelock();
    }

    function isFrozen() external override view returns (bool) {
        return LibDiamond.isFrozen();
    }

    function facetCodeHash(address _facet) external override view returns (bytes32) {
        return LibDiamond.diamondStorage().facetCodeHash[_facet];
    }

    function selectorPaused(bytes4 _selector) external override view returns (bool) {
        return LibDiamond.diamondStorage().selectorPaused[_selector];
    }

    function selectorsPaused(bytes4[] calldata _selectors)
        external
        override
        view
        returns (bool[] memory out)
    {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        out = new bool[](_selectors.length);
        for (uint256 i; i < _selectors.length; ) {
            out[i] = ds.selectorPaused[_selectors[i]];
            unchecked { ++i; }
        }
    }

    function selectorMeta(bytes4 _selector)
        external
        override
        view
        returns (LibDiamond.SelectorMeta memory)
    {
        return LibDiamond.diamondStorage().selectorMeta[_selector];
    }

    function latestInFamily(bytes32 _family) external override view returns (bytes4) {
        return LibDiamond.diamondStorage().latestInFamily[_family];
    }
}
