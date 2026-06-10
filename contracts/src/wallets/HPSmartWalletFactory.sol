// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { LibClone } from "@solady/utils/LibClone.sol";

import { AddressBook } from "@core/AddressBook.sol";

import { HPSmartWallet } from "./HPSmartWallet.sol";
import { IHPWalletRegistry } from "./interfaces/IHPWalletRegistry.sol";

/// @title HPSmartWalletFactory
/// @notice CREATE2 ERC-1967 proxy factory for `HPSmartWallet` (Coinbase-style account factory) that records every
///         new wallet and its initial owners in the central `HPWalletRegistry`.
/// @dev Deployment order: wallet implementation -> registry -> factory, then register the `WALLET_REGISTRY` and
///      `WALLET_FACTORY` AddressProvider keys (both are resolved at call time, so ordering of the keys is free).
contract HPSmartWalletFactory is AddressBook {
    address public immutable implementation;

    event AccountCreated(address indexed account, bytes[] owners, uint256 nonce);

    error ImplementationUndeployed();
    error OwnerRequired();

    constructor(address implementation_, address addressProvider_) payable AddressBook(addressProvider_) {
        if (implementation_.code.length == 0) revert ImplementationUndeployed();
        implementation = implementation_;
    }

    /// @notice Deploys (or returns) the deterministic wallet for `owners` + `nonce` and registers it centrally.
    /// @dev Idempotent: if the wallet is already deployed, it is returned without re-initialization or
    ///      re-registration. The salt covers only owners + nonce, so user settings cannot influence the
    ///      counterfactual address.
    function createAccount(bytes[] calldata owners, uint256 nonce)
        external
        payable
        virtual
        returns (HPSmartWallet account)
    {
        if (owners.length == 0) {
            revert OwnerRequired();
        }

        (bool alreadyDeployed, address accountAddress) =
            LibClone.createDeterministicERC1967(msg.value, implementation, _getSalt(owners, nonce));

        account = HPSmartWallet(payable(accountAddress));

        if (!alreadyDeployed) {
            account.initialize(owners);
            IHPWalletRegistry(_getAddress(_addressKey("WALLET_REGISTRY"))).register(accountAddress, owners);
            emit AccountCreated(accountAddress, owners, nonce);
        }
    }

    /// @notice Counterfactual wallet address for `owners` + `nonce` (used by the client and Turnkey config).
    function getAddress(bytes[] calldata owners, uint256 nonce) external view returns (address) {
        return LibClone.predictDeterministicAddress(initCodeHash(), _getSalt(owners, nonce), address(this));
    }

    function initCodeHash() public view virtual returns (bytes32) {
        return LibClone.initCodeHashERC1967(implementation);
    }

    function _getSalt(bytes[] calldata owners, uint256 nonce) internal pure returns (bytes32) {
        return keccak256(abi.encode(owners, nonce));
    }
}
