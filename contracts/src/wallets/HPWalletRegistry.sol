// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { AddressBook } from "@core/AddressBook.sol";

import { IHPWalletRegistry } from "./interfaces/IHPWalletRegistry.sol";

/// @title HPWalletRegistry
/// @notice Central user-storage contract: every wallet deployed by `HPSmartWalletFactory` is recorded here, keyed
///         by `keccak256(ownerBytes)` for both EOA (32-byte) and passkey (64-byte) owners. Gives the client an
///         instant owner -> wallet lookup on Base plus paginated enumeration of all user wallets.
/// @dev The factory is resolved at call time via the `WALLET_FACTORY` AddressProvider key, which avoids the
///      registry <-> factory circular deployment dependency. Post-creation owner changes are synced by the
///      wallets themselves (gated by `isRegisteredWallet`).
contract HPWalletRegistry is AddressBook, IHPWalletRegistry {
    // --------------------------------------------
    //  Storage
    // --------------------------------------------

    /// @inheritdoc IHPWalletRegistry
    mapping(bytes32 ownerHash => address wallet) public getWallet;

    /// @inheritdoc IHPWalletRegistry
    mapping(address wallet => bool registered) public isRegisteredWallet;

    /// @dev Registration order. Used for enumeration only.
    address[] private _wallets;
    /// @dev 1-based index into `_wallets`; 0 means the wallet is not registered.
    mapping(address wallet => uint256 indexPlusOne) private _walletIndexPlusOne;

    // --------------------------------------------
    //  Events and Errors
    // --------------------------------------------

    event WalletRegistered(address indexed wallet, bytes[] owners);
    event OwnerIndexed(address indexed wallet, bytes32 indexed ownerHash, bytes owner);
    event OwnerDeindexed(address indexed wallet, bytes32 indexed ownerHash, bytes owner);

    error CallerNotFactory();
    error CallerNotRegisteredWallet();
    error ZeroWallet();
    error WalletAlreadyRegistered(address wallet);
    error OwnerAlreadyRegistered(bytes owner, address wallet);
    error OwnerNotRegisteredToWallet(bytes owner, address wallet);

    // --------------------------------------------
    //  Initialization
    // --------------------------------------------

    constructor(address addressProvider_) AddressBook(addressProvider_) { }

    // --------------------------------------------
    //  Modifiers
    // --------------------------------------------

    modifier onlyFactory() {
        if (msg.sender != _getAddress(_addressKey("WALLET_FACTORY"))) revert CallerNotFactory();
        _;
    }

    modifier onlyRegisteredWallet() {
        if (!isRegisteredWallet[msg.sender]) revert CallerNotRegisteredWallet();
        _;
    }

    // --------------------------------------------
    //  Registration (factory)
    // --------------------------------------------

    /// @inheritdoc IHPWalletRegistry
    function register(address wallet, bytes[] calldata owners) external onlyFactory {
        if (wallet == address(0)) revert ZeroWallet();
        if (isRegisteredWallet[wallet]) revert WalletAlreadyRegistered(wallet);

        isRegisteredWallet[wallet] = true;
        _wallets.push(wallet);
        _walletIndexPlusOne[wallet] = _wallets.length;

        for (uint256 i; i < owners.length; ++i) {
            _indexOwner(wallet, owners[i]);
        }

        emit WalletRegistered(wallet, owners);
    }

    // --------------------------------------------
    //  Owner synchronization (wallets)
    // --------------------------------------------

    /// @inheritdoc IHPWalletRegistry
    function addOwner(bytes calldata owner) external onlyRegisteredWallet {
        _indexOwner(msg.sender, owner);
    }

    /// @inheritdoc IHPWalletRegistry
    function removeOwner(bytes calldata owner) external onlyRegisteredWallet {
        bytes32 ownerHash = keccak256(owner);
        if (getWallet[ownerHash] != msg.sender) revert OwnerNotRegisteredToWallet(owner, msg.sender);

        delete getWallet[ownerHash];

        emit OwnerDeindexed(msg.sender, ownerHash, owner);
    }

    /// @dev One wallet per signer key: an owner already mapped elsewhere reverts to keep lookups unambiguous.
    function _indexOwner(address wallet, bytes memory owner) private {
        bytes32 ownerHash = keccak256(owner);

        address current = getWallet[ownerHash];
        if (current != address(0)) revert OwnerAlreadyRegistered(owner, current);

        getWallet[ownerHash] = wallet;

        emit OwnerIndexed(wallet, ownerHash, owner);
    }

    // --------------------------------------------
    //  Lookups
    // --------------------------------------------

    /// @inheritdoc IHPWalletRegistry
    function walletOf(address owner) external view returns (address) {
        return getWallet[keccak256(abi.encode(owner))];
    }

    /// @notice Wallet for a passkey owner (P-256 public key coordinates).
    function walletOfPublicKey(bytes32 x, bytes32 y) external view returns (address) {
        return getWallet[keccak256(abi.encode(x, y))];
    }

    function walletCount() external view returns (uint256) {
        return _wallets.length;
    }

    function walletAt(uint256 index) external view returns (address) {
        return _wallets[index];
    }

    /// @notice Paginated read — prefer this for large sets if RPC limits are hit.
    function getWallets(uint256 offset, uint256 limit) external view returns (address[] memory) {
        return _getWalletsSlice(offset, limit);
    }

    /// @notice Full snapshot (fine for off-chain `eth_call` at moderate sizes; use pagination if not).
    function getAllWallets() external view returns (address[] memory) {
        return _getWalletsSlice(0, _wallets.length);
    }

    function _getWalletsSlice(uint256 offset, uint256 limit) private view returns (address[] memory wallets) {
        uint256 n = _wallets.length;
        if (offset >= n || limit == 0) {
            return new address[](0);
        }
        uint256 end = offset + limit;
        if (end > n) end = n;
        uint256 len = end - offset;
        wallets = new address[](len);
        for (uint256 i; i < len; ++i) {
            wallets[i] = _wallets[offset + i];
        }
    }
}
