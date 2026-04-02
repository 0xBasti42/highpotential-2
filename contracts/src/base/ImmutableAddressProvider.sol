// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AddressProvider } from "@src/AddressProvider.sol";

/// @notice Registry slot is unset or zero for this key
error AddressNotFound();

abstract contract ImmutableAddressProvider {
    AddressProvider public immutable addressProvider;

    constructor(address _addressProvider) {
        addressProvider = AddressProvider(payable(_addressProvider));
    }

    /// @notice `AddressProvider` name key: `keccak256(bytes(name))` (matches `getByName`)
    function _addressKey(string memory name) internal pure returns (bytes32) {
        return keccak256(bytes(name));
    }

    /// @notice Batch version of `_addressKey`
    function _addressKeys(string[] memory names) internal pure returns (bytes32[] memory keys) {
        uint256 len = names.length;
        keys = new bytes32[](len);
        for (uint256 i; i < len; ) {
            keys[i] = keccak256(bytes(names[i]));
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Resolves `key` via `AddressProvider`; reverts if missing or zero
    function getAddress(bytes32 key) internal view returns (address) {
        address returnAddress = addressProvider.get(key);
        if (returnAddress == address(0)) revert AddressNotFound();
        return returnAddress;
    }

    /// @notice Batch version of `getAddress` (single external call into `AddressProvider`).
    function _getAddresses(bytes32[] memory keys) internal view returns (address[] memory addrs) {
        addrs = addressProvider.getMany(keys);
        uint256 len = addrs.length;
        for (uint256 i; i < len; ) {
            if (addrs[i] == address(0)) revert AddressNotFound();
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Resolves `address` via `AddressProvider`; reverts if missing or zero
    function getAddressByName(string memory name) external view returns (address) {
        address returnAddress = addressProvider.getAddress(name);
        if (returnAddress == address(0)) revert AddressNotFound();
        return returnAddress;
    }
}
