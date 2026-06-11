# Audited by [V12](https://v12.sh/)

The only autonomous auditor that finds critical bugs. Not all audits are equal, so stop paying for bad ones. Just use V12. No calls, demos, or intros.

# Inert Owners Bypass Last Guard
**#85775**
- Severity: Low
- Validity: Unreviewed

## Source locations

### `contracts/src/wallets/base/MultiOwnable.sol` (3 locations)
#### Lines 42-58 — _Owner addition increments the owner index, while removal only checks the raw owner count before deleting an owner._

```
    function addOwnerAddress(address owner) external virtual onlyOwner {
        _addOwnerAtIndex(abi.encode(owner), _getMultiOwnableStorage().nextOwnerIndex++);
    }

    function addOwnerPublicKey(bytes32 x, bytes32 y) external virtual onlyOwner {
        _addOwnerAtIndex(abi.encode(x, y), _getMultiOwnableStorage().nextOwnerIndex++);
    }

    /// @notice Removes an owner. The final owner can never be removed, so the wallet always has >=1 controller.
    /// @dev `removeLastOwner` (which the Coinbase base exposes) is intentionally omitted: allowing the owner set
    ///      to reach zero would permanently brick `execute`, owner management, and upgrades.
    function removeOwnerAtIndex(uint256 index, bytes calldata owner) external virtual onlyOwner {
        if (ownerCount() == 1) {
            revert LastOwner();
        }

        _removeOwnerAtIndex(index, owner);
```

⋯
#### Lines 81-84 — _The last-owner guard relies on a syntactic count of stored owner entries._

```
    function ownerCount() public view virtual returns (uint256) {
        MultiOwnableStorage storage $ = _getMultiOwnableStorage();
        return $.nextOwnerIndex - $.removedOwnersCount;
    }
```

⋯
#### Lines 99-110 — _The owner-write chokepoint validates shape, rejects self and duplicates, then stores the payload as an owner._

```
    /// @dev Single chokepoint for all owner writes (initialize / addOwnerAddress / addOwnerPublicKey). Rejects
    ///      uncontrollable owners so the stored set always equals the set of reachable controllers.
    function _addOwnerAtIndex(bytes memory owner, uint256 index) internal virtual {
        OwnerValidation.validate(owner);
        if (keccak256(owner) == keccak256(abi.encode(address(this)))) revert SelfOwnerNotAllowed();
        if (isOwnerBytes(owner)) revert AlreadyOwner(owner);

        MultiOwnableStorage storage $ = _getMultiOwnableStorage();
        $.isOwner[owner] = true;
        $.ownerAtIndex[index] = owner;

        emit AddOwner(index, owner);
```

### `contracts/src/wallets/libraries/OwnerValidation.sol`
#### Lines 22-36 — _Validation accepts any nonzero address-sized value or on-curve P-256 point without a possession or ERC-1271 liveness proof._

```
    function validate(bytes memory owner) internal pure {
        if (owner.length == 32) {
            uint256 value = uint256(bytes32(owner));
            if (value == 0 || value > type(uint160).max) {
                revert InvalidEthereumAddressOwner(owner);
            }
            return;
        }

        if (owner.length == 64) {
            (uint256 x, uint256 y) = abi.decode(owner, (uint256, uint256));
            if (!FCL_Elliptic_ZZ.ecAff_isOnCurve(x, y)) {
                revert InvalidPublicKeyOwner(owner);
            }
            return;
```

### `contracts/src/wallets/HPSmartWallet.sol`
#### Lines 297-323 — _Runtime authorization later requires the indexed owner to produce a valid address or WebAuthn signature._

```
        SignatureWrapper memory sigWrapper = abi.decode(signature, (SignatureWrapper));
        bytes memory ownerBytes = ownerAtIndex(sigWrapper.ownerIndex);

        // Out-of-range or removed owner index: report failure rather than reverting.
        if (ownerBytes.length == 0) {
            return false;
        }

        if (ownerBytes.length == 32) {
            if (uint256(bytes32(ownerBytes)) > type(uint160).max) {
                revert InvalidEthereumAddressOwner(ownerBytes);
            }

            address ownerAddr;
            assembly ("memory-safe") {
                ownerAddr := mload(add(ownerBytes, 32))
            }

            return SignatureCheckerLib.isValidSignatureNow(ownerAddr, hash, sigWrapper.signatureData);
        }

        if (ownerBytes.length == 64) {
            (uint256 x, uint256 y) = abi.decode(ownerBytes, (uint256, uint256));

            WebAuthn.WebAuthnAuth memory auth = abi.decode(sigWrapper.signatureData, (WebAuthn.WebAuthnAuth));

            return WebAuthn.verify({ challenge: abi.encode(hash), requireUV: false, webAuthnAuth: auth, x: x, y: y });
```

### `contracts/lib/solady/src/utils/SignatureCheckerLib.sol` (2 locations)
#### Lines 29-32 — _Address-owner validation distinguishes EOAs from contracts only at signature-check time._

```
    /// @dev Returns whether `signature` is valid for `signer` and `hash`.
    /// If `signer.code.length == 0`, then validate with `ecrecover`, else
    /// it will validate with ERC1271 on `signer`.
    function isValidSignatureNow(address signer, bytes32 hash, bytes memory signature)
```

⋯
#### Lines 62-71 — _Contract address owners must return the ERC-1271 magic value to validate a signature._

```
                let f := shl(224, 0x1626ba7e)
                mstore(m, f) // `bytes4(keccak256("isValidSignature(bytes32,bytes)"))`.
                mstore(add(m, 0x04), hash)
                let d := add(m, 0x24)
                mstore(d, 0x40) // The offset of the `signature` in the calldata.
                // Copy the `signature` over.
                let n := add(0x20, mload(signature))
                let copied := staticcall(gas(), 4, signature, n, add(m, 0x44), n)
                isValid := staticcall(gas(), signer, m, add(returndatasize(), 0x44), d, 0x20)
                isValid := and(eq(mload(d), f), and(isValid, copied))
```

## Description

`MultiOwnable` still allows an authorized owner to store owner payloads that cannot actually authorize the wallet. `addOwnerAddress()` and `addOwnerPublicKey()` both route to `_addOwnerAtIndex()`, but that chokepoint only applies `OwnerValidation.validate()`, rejects the wallet’s own address, and rejects exact duplicates. `OwnerValidation.validate()` accepts any nonzero `uint160` address and any on-curve P-256 point; it does not require the new owner to prove possession of an EOA key, implement ERC-1271, expose a callable control path, or prove knowledge of the P-256 private key. After such an inert payload is added, `removeOwnerAtIndex()` trusts the raw `ownerCount()` and permits removal of the last usable owner because the stored but unreachable payload is counted as an owner. Later wallet authorization depends on the stored index producing a valid ECDSA/ERC-1271 or WebAuthn signature, so a blackhole contract, precompile-style address, burn address, or random on-curve public key leaves the wallet with no reachable controller.

## Root cause

`MultiOwnable` equates syntactic owner payload validity with controller liveness. The final-owner guard is based on `ownerCount()` of stored bytes rather than on proof that at least one remaining owner can actually authorize wallet actions.

## Impact

A wallet can be transitioned into a state with `ownerCount() == 1` but no usable signer, freezing execution, owner rotation, settings changes, and upgrades through normal wallet flows. This requires an owner-authorized action, so the practical impact is a privileged self-brick or co-owner griefing path rather than an unauthenticated takeover.

---

# Empty Initialization Enables Takeover
**#85776**
- Severity: Low
- Validity: Unreviewed

## Source locations

### `contracts/src/wallets/HPSmartWallet.sol`
#### Lines 97-103 — _The external initializer gates only on `nextOwnerIndex()` and then delegates owner setup to the base contract._

```
    function initialize(bytes[] calldata owners) external payable virtual {
        if (nextOwnerIndex() != 0) {
            revert Initialized();
        }

        _initializeOwners(owners);

```

### `contracts/src/wallets/base/MultiOwnable.sol` (2 locations)
#### Lines 37-43 — _Once reinitialized with attacker-controlled owners, the attacker gains owner-gated capabilities such as adding owners._

```
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function addOwnerAddress(address owner) external virtual onlyOwner {
        _addOwnerAtIndex(abi.encode(owner), _getMultiOwnableStorage().nextOwnerIndex++);
```

⋯
#### Lines 90-97 — _The base initializer accepts an empty owner array and writes zero back to `nextOwnerIndex`._

```
    function _initializeOwners(bytes[] memory owners) internal virtual {
        MultiOwnableStorage storage $ = _getMultiOwnableStorage();
        uint256 nextOwnerIndex_ = $.nextOwnerIndex;
        for (uint256 i; i < owners.length; i++) {
            _addOwnerAtIndex(owners[i], nextOwnerIndex_++);
        }
        $.nextOwnerIndex = nextOwnerIndex_;
    }
```

### `contracts/src/wallets/HPSmartWalletFactory.sol`
#### Lines 120-122 — _The non-empty owner check exists only in the factory validation path, not in the wallet initializer._

```
    function _validateOwners(bytes[] calldata owners) internal pure {
        if (owners.length == 0) revert OwnerRequired();
        if (owners.length > MAX_OWNERS) revert TooManyOwners(owners.length);
```

## Description

`MultiOwnable._initializeOwners()` accepts an empty owner array and leaves `nextOwnerIndex` unchanged. `HPSmartWallet.initialize()` uses `nextOwnerIndex() != 0` as its only initialized-state guard before delegating to `_initializeOwners()`, so an empty initialization succeeds while preserving the same sentinel value that marks a fresh proxy. A caller or deployment flow that initializes a proxy with `owners.length == 0` therefore does not lock the initializer, and any later external caller can call `initialize()` again with attacker-controlled owners. The factory path validates non-empty owners before deployment, but that validation lives only in `HPSmartWalletFactory` and is not enforced by the wallet/base initializer itself. This creates a takeover path for any wallet proxy deployed or prepared outside the factory’s guarded `createAccount()` flow and then funded or approved under the assumption it was initialized.

## Root cause

The base initializer does not enforce at least one owner or write a separate initialized flag. The inheriting wallet reuses `nextOwnerIndex` as an initialization sentinel, so empty initialization leaves the proxy externally reinitializable.

## Impact

An attacker can become the owner of a proxy that was empty-initialized and then use normal wallet execution to transfer assets, change owners, or upgrade the implementation. Factory-created wallets are protected by the factory’s non-empty owner check, so the exploit requires an alternate or misconfigured proxy deployment path.

---

# Prepaid gas credits to non-wallets are unrecoverable
**#85777**
- Severity: Low
- Validity: Unreviewed

## Source locations

### `contracts/src/wallets/HPPaymaster.sol` (3 locations)
#### Lines 101-111 — _depositFor credits any address_

```
    function depositFor(address wallet) external payable {
        if (wallet == address(0)) revert ZeroWallet();
        if (msg.value == 0) revert ZeroDeposit();

        gasCredit[wallet] += msg.value;
        totalGasCredit += msg.value;

        entryPoint.depositTo{ value: msg.value }(address(this));

        emit GasCreditDeposited(msg.sender, wallet, msg.value);
    }
```

⋯
#### Line 131 — _consumption gated on isHPWallet_

```
        if (!walletFactory.isHPWallet(sender)) revert WalletNotRegistered(sender);
```

⋯
#### Lines 196-211 — _surplus excludes totalGasCredit; no reclaim path_

```
    function withdrawSurplus(address payable to, uint256 amount) external onlyAdmin {
        if (to == address(0)) revert ZeroWithdrawAddress();

        uint256 available = surplus();
        if (amount > available) revert WithdrawExceedsSurplus(amount, available);

        entryPoint.withdrawTo(to, amount);

        emit SurplusWithdrawn(to, amount);
    }

    /// @notice EntryPoint deposit not backing any user credit.
    function surplus() public view returns (uint256) {
        uint256 deposit = entryPoint.balanceOf(address(this));
        return deposit > totalGasCredit ? deposit - totalGasCredit : 0;
    }
```

## Description

`depositFor` accepts ETH for any `wallet` address (explicitly including counterfactual addresses) and increments both `gasCredit[wallet]` and `totalGasCredit`, moving the ETH into the paymaster's EntryPoint deposit. However, the only function that consumes a credit, `validatePaymasterUserOp`, requires `walletFactory.isHPWallet(sender)` to be true. There is no function to refund or reclaim a credit, and `withdrawSurplus` is bounded by `surplus()`, which subtracts the full `totalGasCredit` from the deposit. As a result, any ETH credited to an address that never becomes a registered HP wallet (a mistyped address, or a counterfactual address whose owner array is invalid and can never be initialized) is permanently locked: it can never be spent as gas and is excluded from the admin-withdrawable surplus.

## Root cause

`depositFor` credits arbitrary addresses with no verification that they are (or can become) registered HP wallets, and the contract provides no mechanism to reclaim credit that can never be spent.

## Impact

ETH routed to credit a counterfactual or mistyped address that never becomes a registered HP wallet is permanently frozen inside the paymaster's EntryPoint deposit. Neither the funder, the wallet, nor the admin can ever recover it, since credits are consumable only by registered wallets and are explicitly excluded from withdrawable surplus.

---

# Permissionless factory resync can freeze wallet credits
**#85778**
- Severity: Low
- Validity: Unreviewed

## Source locations

### `contracts/src/wallets/HPPaymaster.sol` (2 locations)
#### Lines 89-92 — _permissionless syncFactory_

```
    function syncFactory() public {
        walletFactory = IHPWalletFactory(_getAddress(_addressKey("WALLET_FACTORY")));
        emit FactorySynced(address(walletFactory));
    }
```

⋯
#### Line 131 — _sponsorship gated on current factory_

```
        if (!walletFactory.isHPWallet(sender)) revert WalletNotRegistered(sender);
```

## Description

`syncFactory` is permissionless and re-resolves `walletFactory` from the AddressProvider's `WALLET_FACTORY` key, which is mutable by `ADDRESS_MANAGER_ROLE`. `validatePaymasterUserOp` gates every sponsored operation on the currently cached `walletFactory.isHPWallet(sender)`. If the registered `WALLET_FACTORY` is rotated to a new factory that does not carry over the `isHPWallet` flag for wallets deployed by the previous factory, anyone can call `syncFactory` to make the paymaster adopt the new pointer immediately, after which all previously registered wallets fail the `isHPWallet` check and can no longer spend their prepaid `gasCredit`. The trapped credit also remains excluded from admin surplus because it still counts toward `totalGasCredit`.

## Root cause

Wallet legitimacy is resolved through a mutable, permissionlessly-refreshable factory pointer with no migration of `isHPWallet` state, so a factory rotation orphans previously registered wallets' credits.

## Impact

Following a privileged rotation of the `WALLET_FACTORY` registry entry, the prepaid gas credits of every wallet registered under the prior factory become unusable, freezing those funds. The new factory pointer takes effect for sponsorship without any migration of legitimacy flags.

## Proof of concept

### Setup script

```
#!/bin/bash
set -e

# install dependencies
cd contracts && rm -rf out cache && forge build
```

### Invalid reason

Not exploitable through public entry points alone: freezing legacy wallet credits requires a prior privileged `ADDRESS_MANAGER_ROLE` rotation of `AddressProvider`’s `WALLET_FACTORY` (`contracts/src/AddressProvider.sol:87-107`) to an incompatible factory. An external attacker can only call `HPPaymaster.syncFactory()` (`contracts/src/wallets/HPPaymaster.sol:87-92`) after that admin action; they cannot cause the prerequisite registry change themselves, so this is an admin-induced migration/availability hazard rather than a public exploit.
