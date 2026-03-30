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
import { PositionManager } from "@v4-periphery/PositionManager.sol";
import { IPoolInitializer } from "@base/interfaces/IPoolInitializer.sol";
import { ITokenFactory } from "@base/interfaces/ITokenFactory.sol";
import { DERC20 } from "@markets/doppler/DERC20.sol";
import { ITopUpDistributor, Migrator } from "@markets/Migrator.sol";

enum ModuleState {
    NotWhitelisted,
    TokenFactory,
    GovernanceFactory,
    PoolInitializer,
    LiquidityMigrator
}

error WrongModuleState(address module, ModuleState expected, ModuleState actual);
error ArrayLengthsMismatch();
error PoolInitializerMustBeRegistry(address provided);

struct AssetData {
    address numeraire;
    IPoolInitializer poolInitializer;
    address pool;
    address migrationPool;
    uint256 numTokensToSell;
    uint256 totalSupply;
    address integrator;
}

struct CreateParams {
    uint256 initialSupply;
    uint256 numTokensToSell;
    address numeraire;
    ITokenFactory tokenFactory;
    bytes tokenFactoryData;
    IPoolInitializer poolInitializer;
    bytes poolInitializerData;
    bytes liquidityMigratorData;
    address integrator;
    bytes32 salt;
}

event AssetLaunched(address asset, address indexed numeraire, address poolOrHook);
event Migrate(address indexed asset, address indexed pool);
event SetModuleState(address indexed module, ModuleState indexed state);
event Collect(address indexed to, address indexed token, uint256 amount);

error InvalidTokenOrder();
error SenderNotSelf();

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

contract Initializer is Ownable, IPoolInitializer, Migrator {
    using CurrencyLibrary for Currency;
    using SoladySafeTransferLib for address;
    using SafeTransferLib for ERC20;

    DopplerDeployer public immutable deployer;

    mapping(address module => ModuleState state) public getModuleState;
    mapping(address asset => AssetData data) public getAssetData;
    mapping(address token => uint256 amount) public getProtocolFees;
    mapping(address integratorAccount => mapping(address token => uint256 amount)) public getIntegratorFees;

    modifier onlySelf() {
        require(msg.sender == address(this), SenderNotSelf());
        _;
    }

    constructor(
        address owner_,
        IPoolManager poolManager_,
        DopplerDeployer deployer_,
        PositionManager positionManager,
        address locker_,
        IHooks migratorHook_,
        ITopUpDistributor topUpDistributor_
    )
        Ownable(owner_)
        Migrator(poolManager_, positionManager, locker_, migratorHook_, topUpDistributor_)
    {
        deployer = deployer_;
    }

    function _protocolOwner() internal view override returns (address) {
        return owner();
    }

    receive() external payable { }

    function create(CreateParams calldata createData)
        external
        returns (address asset, address pool, address migrationPool)
    {
        _validateModuleState(address(createData.tokenFactory), ModuleState.TokenFactory);
        if (address(createData.poolInitializer) != address(this)) {
            revert PoolInitializerMustBeRegistry(address(createData.poolInitializer));
        }
        _validateModuleState(address(this), ModuleState.PoolInitializer);

        asset = createData.tokenFactory
            .create(
                createData.initialSupply, address(this), address(this), createData.salt, createData.tokenFactoryData
            );

        ERC20(asset).approve(address(this), createData.numTokensToSell);
        pool = _initializeV4Pool(
            asset, createData.numeraire, createData.numTokensToSell, createData.salt, createData.poolInitializerData
        );

        _configureV4Migration(asset, createData.numeraire, createData.liquidityMigratorData);
        migrationPool = address(0);
        DERC20(asset).lockPool(migrationPool);

        uint256 excessAsset = ERC20(asset).balanceOf(address(this));

        if (excessAsset > 0) {
            ERC20(asset).safeTransfer(owner(), excessAsset);
        }

        getAssetData[asset] = AssetData({
            numeraire: createData.numeraire,
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

        _migrate(sqrtPriceX96, token0, token1, owner());

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

    function initialize(
        address asset,
        address numeraire,
        uint256 numTokensToSell,
        bytes32 salt,
        bytes calldata data
    ) external onlySelf returns (address) {
        return _initializeV4Pool(asset, numeraire, numTokensToSell, salt, data);
    }

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

    function _handleFees(address token, address integrator_, uint256 balance, uint256 fees) internal {
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
            getIntegratorFees[integrator_][token] += integratorFees;
        }
    }

    function _validateModuleState(address module, ModuleState state) internal view {
        require(getModuleState[address(module)] == state, WrongModuleState(module, state, getModuleState[module]));
    }
}
