// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Thrown when the caller is not the market registry (`Initializer`)
error SenderNotRegistry();

abstract contract ImmutableRegistry {
    address public immutable registry;

    constructor(address registry_) {
        registry = registry_;
    }

    modifier onlyRegistry() {
        require(msg.sender == registry, SenderNotRegistry());
        _;
    }
}
