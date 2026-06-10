// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { UserOperation06 } from "@account-abstraction/legacy/v06/UserOperation06.sol";
import { WebAuthn } from "@webauthn-sol/WebAuthn.sol";

import { HPSmartWallet } from "@src/wallets/HPSmartWallet.sol";
import { MultiOwnable } from "@src/wallets/base/MultiOwnable.sol";

import { Utils, WebAuthnInfo } from "../../lib/webauthn-sol/test/Utils.sol";
import { WalletTestBase } from "./WalletTestBase.sol";

contract HPSmartWalletAuthTest is WalletTestBase {
    HPSmartWallet internal wallet;

    /// @dev Arbitrary valid secp256r1 scalar for the passkey owner.
    uint256 internal constant P256_PK = uint256(keccak256("hp.passkey.test"));

    function setUp() public override {
        super.setUp();
        wallet = _createWallet(ownerEOA, 0);
    }

    // --------------------------------------------
    //  validateUserOp (EOA owner)
    // --------------------------------------------

    function test_validateUserOp_acceptsEoaOwnerSignature() public {
        UserOperation06 memory op = _baseUserOp(address(wallet), 0);
        bytes32 userOpHash = keccak256("user op");
        op.signature = _eoaSignature(ownerPk, userOpHash, 0);

        vm.prank(entryPointAddr);
        uint256 validationData = wallet.validateUserOp(op, userOpHash, 0);

        assertEq(validationData, 0);
    }

    function test_validateUserOp_rejectsNonOwnerSignature() public {
        (, uint256 strangerPk) = makeAddrAndKey("stranger");
        UserOperation06 memory op = _baseUserOp(address(wallet), 0);
        bytes32 userOpHash = keccak256("user op");
        op.signature = _eoaSignature(strangerPk, userOpHash, 0);

        vm.prank(entryPointAddr);
        uint256 validationData = wallet.validateUserOp(op, userOpHash, 0);

        assertEq(validationData, 1);
    }

    function test_validateUserOp_revertsWhenNotEntryPoint() public {
        UserOperation06 memory op = _baseUserOp(address(wallet), 0);

        vm.expectRevert(MultiOwnable.Unauthorized.selector);
        wallet.validateUserOp(op, keccak256("user op"), 0);
    }

    function test_validateUserOp_paysPrefund() public {
        vm.deal(address(wallet), 1 ether);
        UserOperation06 memory op = _baseUserOp(address(wallet), 0);
        bytes32 userOpHash = keccak256("user op");
        op.signature = _eoaSignature(ownerPk, userOpHash, 0);

        uint256 balanceBefore = entryPointAddr.balance;
        vm.prank(entryPointAddr);
        wallet.validateUserOp(op, userOpHash, 0.1 ether);

        assertEq(entryPointAddr.balance, balanceBefore + 0.1 ether);
    }

    // --------------------------------------------
    //  Replayable nonce key
    // --------------------------------------------

    function test_validateUserOp_revertsReplayableKeyForNormalCall() public {
        uint256 replayableKey = wallet.REPLAYABLE_NONCE_KEY();
        UserOperation06 memory op = _baseUserOp(address(wallet), replayableKey << 64);
        op.callData = abi.encodeCall(HPSmartWallet.execute, (address(0), 0, ""));
        bytes32 userOpHash = keccak256("user op");
        op.signature = _eoaSignature(ownerPk, userOpHash, 0);

        vm.prank(entryPointAddr);
        vm.expectRevert(abi.encodeWithSelector(HPSmartWallet.InvalidNonceKey.selector, replayableKey));
        wallet.validateUserOp(op, userOpHash, 0);
    }

    function test_validateUserOp_revertsNormalKeyForCrossChainCall() public {
        UserOperation06 memory op = _baseUserOp(address(wallet), 0);
        bytes[] memory calls = new bytes[](0);
        op.callData = abi.encodeCall(HPSmartWallet.executeWithoutChainIdValidation, (calls));
        bytes32 userOpHash = keccak256("user op");
        op.signature = _eoaSignature(ownerPk, userOpHash, 0);

        vm.prank(entryPointAddr);
        vm.expectRevert(abi.encodeWithSelector(HPSmartWallet.InvalidNonceKey.selector, 0));
        wallet.validateUserOp(op, userOpHash, 0);
    }

    function test_validateUserOp_crossChainPathSignsChainAgnosticHash() public {
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeCall(MultiOwnable.addOwnerAddress, (makeAddr("newOwner")));

        UserOperation06 memory op = _baseUserOp(address(wallet), wallet.REPLAYABLE_NONCE_KEY() << 64);
        op.callData = abi.encodeCall(HPSmartWallet.executeWithoutChainIdValidation, (calls));
        op.signature = _eoaSignature(ownerPk, wallet.getUserOpHashWithoutChainId(op), 0);

        vm.prank(entryPointAddr);
        // The provided hash is ignored on this path; the wallet re-derives the chain-agnostic hash.
        uint256 validationData = wallet.validateUserOp(op, keccak256("ignored"), 0);

        assertEq(validationData, 0);
    }

    // --------------------------------------------
    //  ERC-1271
    // --------------------------------------------

    function test_isValidSignature_acceptsReplaySafeSignature() public {
        bytes32 hash = keccak256("message");
        bytes memory signature = _eoaSignature(ownerPk, wallet.replaySafeHash(hash), 0);

        assertEq(wallet.isValidSignature(hash, signature), bytes4(0x1626ba7e));
    }

    function test_isValidSignature_rejectsRawHashSignature() public {
        bytes32 hash = keccak256("message");
        bytes memory signature = _eoaSignature(ownerPk, hash, 0);

        assertEq(wallet.isValidSignature(hash, signature), bytes4(0xffffffff));
    }

    // --------------------------------------------
    //  Passkey (WebAuthn) owner
    // --------------------------------------------

    function test_validateUserOp_acceptsPasskeyOwnerSignature() public {
        (uint256 x, uint256 y) = vm.publicKeyP256(P256_PK);
        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(x, y);
        HPSmartWallet passkeyWallet = factory.createAccount(owners, 0);

        UserOperation06 memory op = _baseUserOp(address(passkeyWallet), 0);
        bytes32 userOpHash = keccak256("passkey user op");

        WebAuthnInfo memory info = Utils.getWebAuthnStruct(userOpHash);
        (bytes32 r, bytes32 s) = vm.signP256(P256_PK, info.messageHash);
        s = bytes32(Utils.normalizeS(uint256(s)));

        WebAuthn.WebAuthnAuth memory auth = WebAuthn.WebAuthnAuth({
            authenticatorData: info.authenticatorData,
            clientDataJSON: info.clientDataJSON,
            challengeIndex: 23,
            typeIndex: 1,
            r: uint256(r),
            s: uint256(s)
        });
        op.signature = abi.encode(HPSmartWallet.SignatureWrapper(0, abi.encode(auth)));

        vm.prank(entryPointAddr);
        uint256 validationData = passkeyWallet.validateUserOp(op, userOpHash, 0);

        assertEq(validationData, 0);
    }

    // --------------------------------------------
    //  execute / executeBatch gating
    // --------------------------------------------

    function test_execute_byOwner() public {
        vm.deal(address(wallet), 1 ether);
        address recipient = makeAddr("recipient");

        vm.prank(ownerEOA);
        wallet.execute(recipient, 0.5 ether, "");

        assertEq(recipient.balance, 0.5 ether);
    }

    function test_execute_byEntryPoint() public {
        vm.deal(address(wallet), 1 ether);
        address recipient = makeAddr("recipient");

        vm.prank(entryPointAddr);
        wallet.execute(recipient, 0.5 ether, "");

        assertEq(recipient.balance, 0.5 ether);
    }

    function test_execute_revertsForNonOwner() public {
        vm.prank(makeAddr("stranger"));
        vm.expectRevert(MultiOwnable.Unauthorized.selector);
        wallet.execute(makeAddr("recipient"), 0, "");
    }

    function test_executeBatch_byOwner() public {
        vm.deal(address(wallet), 1 ether);
        address a = makeAddr("recipientA");
        address b = makeAddr("recipientB");

        HPSmartWallet.Call[] memory calls = new HPSmartWallet.Call[](2);
        calls[0] = HPSmartWallet.Call(a, 0.1 ether, "");
        calls[1] = HPSmartWallet.Call(b, 0.2 ether, "");

        vm.prank(ownerEOA);
        wallet.executeBatch(calls);

        assertEq(a.balance, 0.1 ether);
        assertEq(b.balance, 0.2 ether);
    }

    function test_executeWithoutChainIdValidation_rejectsDisallowedSelector() public {
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeCall(HPSmartWallet.execute, (address(0), 0, ""));

        vm.prank(entryPointAddr);
        vm.expectRevert(
            abi.encodeWithSelector(HPSmartWallet.SelectorNotAllowed.selector, HPSmartWallet.execute.selector)
        );
        wallet.executeWithoutChainIdValidation(calls);
    }
}
