// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { IEntryPoint } from "@account-abstraction/legacy/v06/IEntryPoint06.sol";
import { IPaymaster06 } from "@account-abstraction/legacy/v06/IPaymaster06.sol";
import { UserOperation06 } from "@account-abstraction/legacy/v06/UserOperation06.sol";

import { AddressBook } from "@core/AddressBook.sol";

import { IHPWalletRegistry } from "./interfaces/IHPWalletRegistry.sol";

/// @title HPPaymaster
/// @notice ERC-4337 v0.6 deposit paymaster: sponsors gas for registered HPSmartWallets out of per-wallet ETH
///         credits. Credits are funded via `depositFor` (deposit-skim flow, future deposit router, or treasury
///         top-up) and the backing ETH lives as this contract's deposit inside the EntryPoint.
/// @dev Validation-phase rules (ERC-7562):
///      - `registry.isRegisteredWallet[sender]` and `gasCredit[sender]` are sender-associated storage — allowed.
///      - The AddressProvider must NOT be read during validation, so the registry address is cached in this
///        contract's own storage (allowed while staked) and refreshed permissionlessly via `syncRegistry`.
///      Deployment order: registry -> paymaster (constructor resolves WALLET_REGISTRY), then `addStake` and an
///      initial `depositFor`/EntryPoint deposit before the first sponsored op.
contract HPPaymaster is IPaymaster06, AddressBook {
    // --------------------------------------------
    //  Configuration
    // --------------------------------------------

    /// @dev Gas margin charged on top of `actualGasCost` to cover the `postOp` call itself.
    uint256 public constant POST_OP_GAS = 45_000;

    IEntryPoint public immutable entryPoint;

    /// @dev Cached so validation never touches AddressProvider storage (see contract natspec).
    IHPWalletRegistry public registry;

    mapping(address wallet => uint256 creditWei) public gasCredit;

    /// @dev Sum of all outstanding credits; EntryPoint deposit above this is withdrawable surplus.
    uint256 public totalGasCredit;

    // --------------------------------------------
    //  Events and Errors
    // --------------------------------------------

    event GasCreditDeposited(address indexed funder, address indexed wallet, uint256 amount);
    event GasCreditUsed(address indexed wallet, uint256 amount);
    event RegistrySynced(address indexed registry);
    event SurplusWithdrawn(address indexed to, uint256 amount);

    error NotEntryPoint();
    error NotAdmin();
    error ZeroEntryPoint();
    error ZeroWallet();
    error ZeroDeposit();
    error ZeroWithdrawAddress();
    error WalletNotRegistered(address wallet);
    error InsufficientGasCredit(address wallet, uint256 credit, uint256 required);
    error WithdrawExceedsSurplus(uint256 requested, uint256 surplus);

    // --------------------------------------------
    //  Modifiers
    // --------------------------------------------

    modifier onlyEntryPoint() {
        if (msg.sender != address(entryPoint)) revert NotEntryPoint();
        _;
    }

    /// @dev Admin = holder of the AddressProvider's DEFAULT_ADMIN_ROLE; no separate ownership system.
    modifier onlyAdmin() {
        if (!addressProvider.hasRole(bytes32(0), msg.sender)) revert NotAdmin();
        _;
    }

    // --------------------------------------------
    //  Initialization
    // --------------------------------------------

    constructor(address addressProvider_, address entryPoint_) AddressBook(addressProvider_) {
        if (entryPoint_ == address(0)) revert ZeroEntryPoint();
        entryPoint = IEntryPoint(entryPoint_);
        syncRegistry();
    }

    /// @notice Re-resolves the registry from the AddressProvider. Permissionless: the provider is the source
    ///         of truth and its mutations are already role-gated.
    function syncRegistry() public {
        registry = IHPWalletRegistry(_getAddress(_addressKey("WALLET_REGISTRY")));
        emit RegistrySynced(address(registry));
    }

    // --------------------------------------------
    //  Funding
    // --------------------------------------------

    /// @notice Credits `wallet` with `msg.value` of gas allowance and moves the ETH into the EntryPoint deposit.
    /// @dev Callable by anyone (treasury script, deposit router, or the user). `wallet` may be a counterfactual
    ///      address — credits can be funded before the wallet is deployed.
    function depositFor(address wallet) external payable {
        if (wallet == address(0)) revert ZeroWallet();
        if (msg.value == 0) revert ZeroDeposit();

        gasCredit[wallet] += msg.value;
        totalGasCredit += msg.value;

        entryPoint.depositTo{ value: msg.value }(address(this));

        emit GasCreditDeposited(msg.sender, wallet, msg.value);
    }

    // --------------------------------------------
    //  ERC-4337 paymaster
    // --------------------------------------------

    /// @inheritdoc IPaymaster06
    function validatePaymasterUserOp(UserOperation06 calldata userOp, bytes32, uint256 maxCost)
        external
        view
        onlyEntryPoint
        returns (bytes memory context, uint256 validationData)
    {
        address sender = userOp.sender;

        // Wallet deployment (initCode) runs before paymaster validation, so freshly created wallets are
        // already registered by the factory at this point.
        if (!registry.isRegisteredWallet(sender)) revert WalletNotRegistered(sender);

        uint256 required = maxCost + POST_OP_GAS * userOp.maxFeePerGas;
        uint256 credit = gasCredit[sender];
        if (credit < required) revert InsufficientGasCredit(sender, credit, required);

        return (abi.encode(sender), 0);
    }

    /// @inheritdoc IPaymaster06
    /// @dev Never reverts: a postOp revert would force the EntryPoint to re-execute in `postOpReverted` mode.
    ///      The charge is clamped to the remaining credit; validation guarantees the clamp is a no-op in
    ///      practice (credit covered maxCost + margin).
    function postOp(PostOpMode, bytes calldata context, uint256 actualGasCost) external onlyEntryPoint {
        address wallet = abi.decode(context, (address));

        uint256 charge = actualGasCost + POST_OP_GAS * tx.gasprice;
        uint256 credit = gasCredit[wallet];
        if (charge > credit) charge = credit;

        unchecked {
            gasCredit[wallet] = credit - charge;
            totalGasCredit -= charge;
        }

        emit GasCreditUsed(wallet, charge);
    }

    // --------------------------------------------
    //  EntryPoint stake / deposit administration
    // --------------------------------------------

    function addStake(uint32 unstakeDelaySec) external payable onlyAdmin {
        entryPoint.addStake{ value: msg.value }(unstakeDelaySec);
    }

    function unlockStake() external onlyAdmin {
        entryPoint.unlockStake();
    }

    function withdrawStake(address payable to) external onlyAdmin {
        if (to == address(0)) revert ZeroWithdrawAddress();
        entryPoint.withdrawStake(to);
    }

    /// @notice Withdraws EntryPoint deposit above the sum of outstanding user credits (e.g. accumulated
    ///         postOp margins). User credits themselves can never be withdrawn by the platform.
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
}
