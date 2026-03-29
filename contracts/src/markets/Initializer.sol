// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { Ownable } from "@oz/contracts/access/Ownable.sol";
import { Math } from "@oz/contracts/utils/math/Math.sol";
import { ERC20, SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { SafeTransferLib as SoladySafeTransferLib } from "@solady/utils/SafeTransferLib.sol";
import { Doppler } from "@doppler/initializers/Doppler.sol";
import { IHooks, IPoolManager, PoolKey } from "@v4-core/PoolManager.sol";
import { LPFeeLibrary } from "@v4-core/libraries/LPFeeLibrary.sol";
import { TickMath } from "@v4-core/libraries/TickMath.sol";
import { Currency, CurrencyLibrary } from "@v4-core/types/Currency.sol";
import { IGovernanceFactory } from "@base/interfaces/IGovernanceFactory.sol";
import { ILiquidityMigrator } from "@base/interfaces/ILiquidityMigrator.sol";
import { IPoolInitializer } from "@base/interfaces/IPoolInitializer.sol";
import { ITokenFactory } from "@base/interfaces/ITokenFactory.sol";
import { DERC20 } from "@markets/doppler/DERC20.sol";

enum ModuleState {
    NotWhitelisted,
    TokenFactory,
    GovernanceFactory,
    PoolInitializer,
    LiquidityMigrator
}

/// @notice Thrown when the module state is not the expected one
error WrongModuleState(address module, ModuleState expected, ModuleState actual);

/// @notice Thrown when the lengths of two arrays do not match
error ArrayLengthsMismatch();

/// @notice Thrown when `CreateParams.poolInitializer` is not this registry
error PoolInitializerMustBeRegistry(address provided);

struct AssetData {
    address numeraire; // standardize 
    address timelock; // delete
    address governance; // delete
    ILiquidityMigrator liquidityMigrator; // standardize to AddressProvider
    IPoolInitializer poolInitializer; // standardize to AddressProvider
    address pool; // change to PoolKey
    address migrationPool; // change to PoolKey
    uint256 numTokensToSell; // standardize
    uint256 totalSupply; // standardize
    address integrator; // standardize to AddressProvider (HPTreasury Multisig)
}

struct CreateParams {
    uint256 initialSupply; // standardize
    uint256 numTokensToSell; // standardize
    address numeraire; // standardize
    ITokenFactory tokenFactory; // standardize in AddressProvider
    bytes tokenFactoryData; // modify
    IGovernanceFactory governanceFactory; // delete
    bytes governanceFactoryData; // delete
    IPoolInitializer poolInitializer; // standardize in AddressProvider
    bytes poolInitializerData; // standardize
    ILiquidityMigrator liquidityMigrator; // standardize in AddressProvider
    bytes liquidityMigratorData; // standardize
    address integrator; // standardize in AddressProvider (HPTreasury Multisig)
    bytes32 salt; // can regenerate locally
}

/// @notice Emitted when a new asset token is created via the registry
event AssetLaunched(address asset, address indexed numeraire, address poolOrHook);

/// @notice Emitted when an asset token is migrated
event Migrate(address indexed asset, address indexed pool);

/// @notice Emitted when the state of a module is set
event SetModuleState(address indexed module, ModuleState indexed state);

/// @notice Emitted when fees are collected
event Collect(address indexed to, address indexed token, uint256 amount);

error InvalidTokenOrder();

/// @notice Only the registry contract may call (used for `IPoolInitializer` surface)
error SenderNotSelf();

/// @title Initializer | HighPotential — market registry and Uniswap V4 + Doppler pool bootstrap
contract DopplerDeployer {
    IPoolManager public poolManager;

    constructor(IPoolManager poolManager_) {
        poolManager = poolManager_;
    }

    function deploy(uint256 numTokensToSell, bytes32 salt, bytes calldata data) external returns (Doppler) {
        (
            uint256 minimumProceeds,
            uint256 maximumProceeds,
            uint256 startingTime,
            uint256 endingTime,
            int24 startingTick,
            int24 endingTick,
            uint256 epochLength,
            int24 gamma,
            bool isToken0,
            uint256 numPDSlugs,
            uint24 lpFee,
        ) = abi.decode(
            data, (uint256, uint256, uint256, uint256, int24, int24, uint256, int24, bool, uint256, uint24, int24)
        );

        return new Doppler{ salt: salt }(
            poolManager,
            numTokensToSell,
            minimumProceeds,
            maximumProceeds,
            startingTime,
            endingTime,
            startingTick,
            endingTick,
            epochLength,
            gamma,
            isToken0,
            numPDSlugs,
            msg.sender,
            lpFee
        );
    }
}

contract Initializer is Ownable, IPoolInitializer {
    using CurrencyLibrary for Currency;
    using SoladySafeTransferLib for address;
    using SafeTransferLib for ERC20;

    IPoolManager public immutable poolManager;
    DopplerDeployer public immutable deployer;

    mapping(address module => ModuleState state) public getModuleState; // keep or call AddressProvider?
    mapping(address asset => AssetData data) public getAssetData; // keep
    mapping(address token => uint256 amount) public getProtocolFees;
    mapping(address integrator => mapping(address token => uint256 amount)) public getIntegratorFees;

    modifier onlySelf() {
        require(msg.sender == address(this), SenderNotSelf());
        _;
    }

    constructor(address owner_, IPoolManager poolManager_, DopplerDeployer deployer_) Ownable(owner_) {
        poolManager = poolManager_;
        deployer = deployer_;
    }

    receive() external payable { }

    function create(CreateParams calldata createData)
        external
        returns (address asset, address pool, address governance, address timelock, address migrationPool)
    {
        _validateModuleState(address(createData.tokenFactory), ModuleState.TokenFactory);
        _validateModuleState(address(createData.governanceFactory), ModuleState.GovernanceFactory);
        _validateModuleState(address(createData.liquidityMigrator), ModuleState.LiquidityMigrator);
        if (address(createData.poolInitializer) != address(this)) {
            revert PoolInitializerMustBeRegistry(address(createData.poolInitializer));
        }
        _validateModuleState(address(this), ModuleState.PoolInitializer);

        asset = createData.tokenFactory
            .create(
                createData.initialSupply, address(this), address(this), createData.salt, createData.tokenFactoryData
            );

        (governance, timelock) = createData.governanceFactory.create(asset, createData.governanceFactoryData); // delete

        ERC20(asset).approve(address(this), createData.numTokensToSell);
        pool = _initializeV4Pool(
            asset, createData.numeraire, createData.numTokensToSell, createData.salt, createData.poolInitializerData
        );

        migrationPool =
            createData.liquidityMigrator.initialize(asset, createData.numeraire, createData.liquidityMigratorData);
        DERC20(asset).lockPool(migrationPool);

        uint256 excessAsset = ERC20(asset).balanceOf(address(this));

        if (excessAsset > 0) {
            ERC20(asset).safeTransfer(timelock, excessAsset);
        }

        getAssetData[asset] = AssetData({
            numeraire: createData.numeraire,
            timelock: timelock,
            governance: governance,
            liquidityMigrator: createData.liquidityMigrator,
            poolInitializer: IPoolInitializer(address(this)),
            pool: pool,
            migrationPool: migrationPool,
            numTokensToSell: createData.numTokensToSell,
            totalSupply: createData.initialSupply,
            integrator: createData.integrator == address(0) ? owner() : createData.integrator
        });

        emit AssetLaunched(asset, createData.numeraire, pool);
    }

    function migrate(address asset) external {
        AssetData memory assetData = getAssetData[asset];

        DERC20(asset).unlockPool();
        try Ownable(asset).owner() returns (address tokenOwner) {
            if (tokenOwner == address(this)) {
                Ownable(asset).transferOwnership(assetData.timelock);
            }
        } catch { }

        (
            uint160 sqrtPriceX96,
            address token0,
            uint128 fees0,
            uint128 balance0,
            address token1,
            uint128 fees1,
            uint128 balance1
        ) = _exitLiquidity(assetData.pool);

        _handleFees(token0, assetData.integrator, balance0, fees0);
        _handleFees(token1, assetData.integrator, balance1, fees1);

        address liquidityMigrator = address(assetData.liquidityMigrator);

        if (token0 == address(0)) {
            SafeTransferLib.safeTransferETH(liquidityMigrator, balance0 - fees0);
        } else {
            ERC20(token0).safeTransfer(liquidityMigrator, balance0 - fees0);
        }

        ERC20(token1).safeTransfer(liquidityMigrator, balance1 - fees1);

        assetData.liquidityMigrator.migrate(sqrtPriceX96, token0, token1, assetData.timelock);

        emit Migrate(asset, assetData.migrationPool);
    }

    function setModuleState(address[] calldata modules, ModuleState[] calldata states) external onlyOwner {
        uint256 length = modules.length;

        if (length != states.length) {
            revert ArrayLengthsMismatch();
        }

        for (uint256 i; i < length; ++i) {
            getModuleState[modules[i]] = states[i];
            emit SetModuleState(modules[i], states[i]);
        }
    }

    function collectProtocolFees(address to, address token, uint256 amount) external onlyOwner {
        getProtocolFees[token] -= amount;

        if (token == address(0)) {
            SafeTransferLib.safeTransferETH(to, amount);
        } else {
            ERC20(token).safeTransfer(to, amount);
        }

        emit Collect(to, token, amount);
    }

    function collectIntegratorFees(address to, address token, uint256 amount) external {
        getIntegratorFees[msg.sender][token] -= amount;

        if (token == address(0)) {
            SafeTransferLib.safeTransferETH(to, amount);
        } else {
            ERC20(token).safeTransfer(to, amount);
        }

        emit Collect(to, token, amount);
    }

    /// @inheritdoc IPoolInitializer
    function initialize(
        address asset,
        address numeraire,
        uint256 numTokensToSell,
        bytes32 salt,
        bytes calldata data
    ) external onlySelf returns (address) {
        return _initializeV4Pool(asset, numeraire, numTokensToSell, salt, data);
    }

    /// @inheritdoc IPoolInitializer
    function exitLiquidity(address hook)
        external
        onlySelf
        returns (
            uint160 sqrtPriceX96,
            address token0,
            uint128 fees0,
            uint128 balance0,
            address token1,
            uint128 fees1,
            uint128 balance1
        )
    {
        return _exitLiquidity(hook);
    }

    function _initializeV4Pool(
        address asset,
        address numeraire,
        uint256 numTokensToSell,
        bytes32 salt,
        bytes calldata data
    ) internal returns (address hookAddress) {
        (,,,, int24 startingTick,,,, bool isToken0,,, int24 tickSpacing) = abi.decode(
            data, (uint256, uint256, uint256, uint256, int24, int24, uint256, int24, bool, uint256, uint24, int24)
        );

        Doppler doppler = deployer.deploy(numTokensToSell, salt, data);

        if (isToken0 && asset > numeraire || !isToken0 && asset < numeraire) {
            revert InvalidTokenOrder();
        }

        PoolKey memory poolKey = PoolKey({
            currency0: isToken0 ? Currency.wrap(asset) : Currency.wrap(numeraire),
            currency1: isToken0 ? Currency.wrap(numeraire) : Currency.wrap(asset),
            hooks: IHooks(doppler),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: tickSpacing
        });

        address(asset).safeTransferFrom(address(this), address(doppler), numTokensToSell);

        poolManager.initialize(poolKey, TickMath.getSqrtPriceAtTick(startingTick));

        emit Create(address(doppler), asset, numeraire);

        return address(doppler);
    }

    function _exitLiquidity(address hook)
        internal
        returns (
            uint160 sqrtPriceX96,
            address token0,
            uint128 fees0,
            uint128 balance0,
            address token1,
            uint128 fees1,
            uint128 balance1
        )
    {
        (sqrtPriceX96, token0, fees0, balance0, token1, fees1, balance1) =
            Doppler(payable(hook)).migrate(address(this));
    }

    function _handleFees(address token, address integrator, uint256 balance, uint256 fees) internal {
        if (fees > 0) {
            uint256 protocolLpFees = fees / 20;
            uint256 protocolProceedsFees = (balance - fees) / 1000;
            uint256 protocolFees = Math.max(protocolLpFees, protocolProceedsFees);
            uint256 maxProtocolFees = fees / 5;
            uint256 integratorFees;

            (integratorFees, protocolFees) = protocolFees > maxProtocolFees
                ? (fees - maxProtocolFees, maxProtocolFees)
                : (fees - protocolFees, protocolFees);

            getProtocolFees[token] += protocolFees;
            getIntegratorFees[integrator][token] += integratorFees;
        }
    }

    function _validateModuleState(address module, ModuleState state) internal view {
        require(getModuleState[address(module)] == state, WrongModuleState(module, state, getModuleState[module]));
    }
}
