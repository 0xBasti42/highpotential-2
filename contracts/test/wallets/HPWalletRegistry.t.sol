// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { HPSmartWallet } from "@src/wallets/HPSmartWallet.sol";
import { HPWalletRegistry } from "@src/wallets/HPWalletRegistry.sol";

import { WalletTestBase } from "./WalletTestBase.sol";

contract HPWalletRegistryTest is WalletTestBase {
    // --------------------------------------------
    //  Gating
    // --------------------------------------------

    function test_register_revertsForNonFactory() public {
        vm.prank(makeAddr("stranger"));
        vm.expectRevert(HPWalletRegistry.CallerNotFactory.selector);
        registry.register(makeAddr("wallet"), _singleOwner(ownerEOA));
    }

    function test_addOwner_revertsForNonRegisteredWallet() public {
        vm.prank(makeAddr("stranger"));
        vm.expectRevert(HPWalletRegistry.CallerNotRegisteredWallet.selector);
        registry.addOwner(abi.encode(ownerEOA));
    }

    function test_removeOwner_revertsForNonRegisteredWallet() public {
        vm.prank(makeAddr("stranger"));
        vm.expectRevert(HPWalletRegistry.CallerNotRegisteredWallet.selector);
        registry.removeOwner(abi.encode(ownerEOA));
    }

    // --------------------------------------------
    //  Lookups
    // --------------------------------------------

    function test_lookups_eoaOwner() public {
        HPSmartWallet wallet = _createWallet(ownerEOA, 0);

        assertEq(registry.walletOf(ownerEOA), address(wallet));
        assertEq(registry.getWallet(keccak256(abi.encode(ownerEOA))), address(wallet));
        assertEq(registry.walletOf(makeAddr("unknown")), address(0));
    }

    function test_lookups_passkeyOwner() public {
        (uint256 x, uint256 y) = vm.publicKeyP256(uint256(keccak256("hp.registry.passkey")));
        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(x, y);

        HPSmartWallet wallet = factory.createAccount(owners, 0);

        assertEq(registry.walletOfPublicKey(bytes32(x), bytes32(y)), address(wallet));
        assertEq(registry.getWallet(keccak256(abi.encode(x, y))), address(wallet));
    }

    function test_oneWalletPerOwnerKey() public {
        _createWallet(ownerEOA, 0);

        // Same signer key cannot be the initial owner of a second wallet: registration reverts.
        bytes[] memory owners = _singleOwner(ownerEOA);
        vm.expectRevert();
        factory.createAccount(owners, 1);
    }

    function test_addOwner_revertsWhenOwnerBelongsToAnotherWallet() public {
        HPSmartWallet walletA = _createWallet(ownerEOA, 0);

        (address otherOwner,) = makeAddrAndKey("otherOwner");
        HPSmartWallet walletB = _createWallet(otherOwner, 0);

        // walletB's owner tries to claim walletA's signer key.
        vm.prank(otherOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                HPWalletRegistry.OwnerAlreadyRegistered.selector, abi.encode(ownerEOA), address(walletA)
            )
        );
        walletB.addOwnerAddress(ownerEOA);
    }

    // --------------------------------------------
    //  Owner synchronization via wallet
    // --------------------------------------------

    function test_ownerAddSync() public {
        HPSmartWallet wallet = _createWallet(ownerEOA, 0);
        address newOwner = makeAddr("newOwner");

        vm.prank(ownerEOA);
        wallet.addOwnerAddress(newOwner);

        assertTrue(wallet.isOwnerAddress(newOwner));
        assertEq(registry.walletOf(newOwner), address(wallet));
    }

    function test_ownerRemoveSync() public {
        HPSmartWallet wallet = _createWallet(ownerEOA, 0);
        address newOwner = makeAddr("newOwner");

        vm.startPrank(ownerEOA);
        wallet.addOwnerAddress(newOwner);
        wallet.removeOwnerAtIndex(1, abi.encode(newOwner));
        vm.stopPrank();

        assertFalse(wallet.isOwnerAddress(newOwner));
        assertEq(registry.walletOf(newOwner), address(0));
        // The remaining owner is untouched.
        assertEq(registry.walletOf(ownerEOA), address(wallet));
    }

    function test_passkeyOwnerAddSync() public {
        HPSmartWallet wallet = _createWallet(ownerEOA, 0);
        (uint256 x, uint256 y) = vm.publicKeyP256(uint256(keccak256("hp.registry.passkey.added")));

        vm.prank(ownerEOA);
        wallet.addOwnerPublicKey(bytes32(x), bytes32(y));

        assertTrue(wallet.isOwnerPublicKey(bytes32(x), bytes32(y)));
        assertEq(registry.walletOfPublicKey(bytes32(x), bytes32(y)), address(wallet));
    }

    // --------------------------------------------
    //  Enumeration
    // --------------------------------------------

    function test_enumerationAndPagination() public {
        address[] memory expected = new address[](3);
        for (uint256 i; i < 3; ++i) {
            (address owner,) = makeAddrAndKey(string(abi.encodePacked("user", i)));
            expected[i] = address(_createWallet(owner, 0));
        }

        assertEq(registry.walletCount(), 3);

        address[] memory all = registry.getAllWallets();
        assertEq(all.length, 3);
        for (uint256 i; i < 3; ++i) {
            assertEq(all[i], expected[i]);
            assertEq(registry.walletAt(i), expected[i]);
        }

        address[] memory page = registry.getWallets(1, 1);
        assertEq(page.length, 1);
        assertEq(page[0], expected[1]);

        // Limit past the end is clamped; offset past the end returns empty.
        assertEq(registry.getWallets(2, 10).length, 1);
        assertEq(registry.getWallets(3, 1).length, 0);
        assertEq(registry.getWallets(0, 0).length, 0);
    }
}
