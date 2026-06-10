// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

/// @title IHPWalletRegistry
/// @notice Central user-storage contract: maps owner keys (EOA or passkey) to their HPSmartWallet.
interface IHPWalletRegistry {
    /// @notice Records a freshly deployed wallet and its initial owners. Factory-only.
    function register(address wallet, bytes[] calldata owners) external;

    /// @notice Indexes an owner added post-creation. Callable only by registered wallets.
    function addOwner(bytes calldata owner) external;

    /// @notice De-indexes an owner removed post-creation. Callable only by registered wallets.
    function removeOwner(bytes calldata owner) external;

    function isRegisteredWallet(address wallet) external view returns (bool);

    /// @notice Wallet for `keccak256(ownerBytes)`; `address(0)` if unknown.
    function getWallet(bytes32 ownerHash) external view returns (address);

    /// @notice Convenience lookup for the common EOA-owner case.
    function walletOf(address owner) external view returns (address);
}
