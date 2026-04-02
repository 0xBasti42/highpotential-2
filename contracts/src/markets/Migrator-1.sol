// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { ERC20 } from "@solmate/utils/SafeTransferLib.sol";
import { SafeTransferLib } from "@solady/utils/SafeTransferLib.sol";
import { IHooks } from "@v4-core/interfaces/IHooks.sol";
import { IPoolManager } from "@v4-core/interfaces/IPoolManager.sol";
import { LPFeeLibrary } from "@v4-core/libraries/LPFeeLibrary.sol";
import { StateLibrary } from "@v4-core/libraries/StateLibrary.sol";
import { TickMath } from "@v4-core/libraries/TickMath.sol";
import { Currency, CurrencyLibrary } from "@v4-core/types/Currency.sol";
import { PoolId, PoolIdLibrary } from "@v4-core/types/PoolId.sol";
import { PoolKey } from "@v4-core/types/PoolKey.sol";
import { PositionManager } from "@v4-periphery/PositionManager.sol";
import { Actions } from "@v4-periphery/libraries/Actions.sol";
import { LiquidityAmounts } from "@v4-periphery/libraries/LiquidityAmounts.sol";
import { isTickSpacingValid } from "@markets/libraries/TickLibrary.sol";
import {
    BeneficiaryData,
    MIN_PROTOCOL_OWNER_SHARES,
    storeBeneficiaries
} from "@markets/types/BeneficiaryData.sol";
import { WAD } from "@markets/types/Wad.sol";

/// @dev Canonical ordering for v4 pairs: token0 < token1
address constant DEAD_ADDRESS = address(0xdead);

struct SplitConfiguration {
    address recipient;
    bool isToken0;
    uint256 share;
}

uint256 constant MAX_SPLIT_SHARE = 0.5e18;

error InvalidSplitRecipient();
error SplitShareTooHigh(uint256 actual, uint256 maximum);

event DistributeSplit(address indexed token0, address indexed token1, address indexed recipient, uint256 amount);

interface ITopUpDistributor {
    function pullUp(address token0, address token1, address recipient) external;
}

abstract contract ProceedsSplitterBase {
    ITopUpDistributor public immutable TOP_UP_DISTRIBUTOR;
    mapping(address token0 => mapping(address token1 => SplitConfiguration config)) public splitConfigurationOf;

    constructor(ITopUpDistributor topUpDistributor_) {
        TOP_UP_DISTRIBUTOR = topUpDistributor_;
    }

    function _setSplit(address token0, address token1, SplitConfiguration memory config) internal {
        require(config.recipient != address(0), InvalidSplitRecipient());
        require(config.share <= MAX_SPLIT_SHARE, SplitShareTooHigh(config.share, MAX_SPLIT_SHARE));
        splitConfigurationOf[token0][token1] = config;
    }

    function _distributeSplit(
        address token0,
        address token1,
        uint256 balance0,
        uint256 balance1
    ) internal returns (uint256 balanceLeft0, uint256 balanceLeft1) {
        SplitConfiguration memory config = splitConfigurationOf[token0][token1];

        balanceLeft0 = balance0;
        balanceLeft1 = balance1;

        address numeraire;
        uint256 splitAmount;

        if (config.isToken0) {
            numeraire = token1;
            splitAmount = balance1 * config.share / WAD;
            balanceLeft1 = balance1 - splitAmount;
        } else {
            numeraire = token0;
            splitAmount = balance0 * config.share / WAD;
            balanceLeft0 = balance0 - splitAmount;
        }

        TOP_UP_DISTRIBUTOR.pullUp(token0, token1, config.recipient);
        if (splitAmount == 0) return (balance0, balance1);

        emit DistributeSplit(token0, token1, config.recipient, splitAmount);

        if (numeraire == address(0)) {
            SafeTransferLib.safeTransferETH(config.recipient, splitAmount);
        } else {
            SafeTransferLib.safeTransfer(numeraire, config.recipient, splitAmount);
        }
    }
}

struct V4MigrationPlan {
    PoolKey poolKey;
    uint32 lockDuration;
    BeneficiaryData[] beneficiaries;
}

/// @dev Emitted when liquidity is migrated into the post-Doppler v4 pool
event V4PoolMigrated(
    PoolId indexed poolId,
    uint160 sqrtPriceX96,
    int24 lowerTick,
    int24 upperTick,
    uint256 liquidity,
    uint256 reserves0,
    uint256 reserves1
);

error TickOutOfRange();
error ZeroLiquidity();

/**
 * @title Migrator
 * @notice Uniswap V4 migrator logic (former `UniswapV4MigratorSplit.migrate`) inlined for the registry.
 */
abstract contract Migrator is ProceedsSplitterBase {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    IPoolManager public immutable poolManager;
    PositionManager public immutable positionManager;
    address public immutable locker;
    IHooks public immutable migratorHook;

    mapping(address token0 => mapping(address token1 => V4MigrationPlan)) public getMigrationPlan;

    constructor(
        IPoolManager poolManager_,
        PositionManager positionManager_,
        address locker_,
        IHooks migratorHook_,
        ITopUpDistributor topUpDistributor_
    ) ProceedsSplitterBase(topUpDistributor_) {
        poolManager = poolManager_;
        positionManager = positionManager_;
        locker = locker_;
        migratorHook = migratorHook_;
    }

    receive() external payable { }

    function _protocolOwner() internal view virtual returns (address);

    /// @dev Records the post-bootstrap pool key and locker config (replaces `ILiquidityMigrator.initialize`).
    function _configureV4Migration(address asset, address numeraire, bytes calldata liquidityMigratorData)
        internal
    {
        (
            uint24 fee,
            int24 tickSpacing,
            uint32 lockDuration,
            BeneficiaryData[] memory beneficiaries,
            address proceedsRecipient,
            uint256 proceedsShare
        ) = abi.decode(liquidityMigratorData, (uint24, int24, uint32, BeneficiaryData[], address, uint256));

        isTickSpacingValid(tickSpacing);
        LPFeeLibrary.validate(fee);
        storeBeneficiaries(
            PoolId.wrap(0),
            beneficiaries,
            _protocolOwner(),
            MIN_PROTOCOL_OWNER_SHARES,
            _storeBeneficiaryNoOp
        );

        PoolKey memory poolKey = PoolKey({
            currency0: asset < numeraire ? Currency.wrap(asset) : Currency.wrap(numeraire),
            currency1: asset < numeraire ? Currency.wrap(numeraire) : Currency.wrap(asset),
            hooks: migratorHook,
            fee: fee,
            tickSpacing: tickSpacing
        });

        getMigrationPlan[Currency.unwrap(poolKey.currency0)][Currency.unwrap(poolKey.currency1)] = V4MigrationPlan({
            poolKey: poolKey,
            lockDuration: lockDuration,
            beneficiaries: beneficiaries
        });

        if (proceedsRecipient != address(0)) {
            _setSplit(
                Currency.unwrap(poolKey.currency0),
                Currency.unwrap(poolKey.currency1),
                SplitConfiguration({ recipient: proceedsRecipient, isToken0: asset < numeraire, share: proceedsShare })
            );
        }
    }

    /// @dev Performs pool init + LP minting (tokens must already be held by this contract).
    function _migrate(uint160 sqrtPriceX96, address token0, address token1, address recipient)
        internal
        returns (uint256 liquidity)
    {
        V4MigrationPlan memory plan = getMigrationPlan[token0][token1];
        PoolKey memory poolKey = plan.poolKey;

        bool isNoOpGovernance = recipient == DEAD_ADDRESS;

        int24 currentTick = poolManager.initialize(poolKey, sqrtPriceX96);

        uint256 balance1 = ERC20(token1).balanceOf(address(this));
        uint256 balance0 = token0 == address(0) ? address(this).balance : ERC20(token0).balanceOf(address(this));

        if (splitConfigurationOf[token0][token1].recipient != address(0)) {
            (balance0, balance1) = _distributeSplit(token0, token1, balance0, balance1);
        }

        int24 lowerTick = TickMath.minUsableTick(poolKey.tickSpacing);
        int24 upperTick = TickMath.maxUsableTick(poolKey.tickSpacing);

        currentTick = currentTick / poolKey.tickSpacing * poolKey.tickSpacing;

        if (currentTick < lowerTick || currentTick > upperTick) revert TickOutOfRange();

        uint160 belowPriceLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(lowerTick),
            TickMath.getSqrtPriceAtTick(currentTick - poolKey.tickSpacing),
            0,
            balance1 == 0 ? 0 : uint128(balance1) - 1
        );

        uint160 abovePriceLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(currentTick + poolKey.tickSpacing),
            TickMath.getSqrtPriceAtTick(upperTick),
            balance0 == 0 ? 0 : uint128(balance0) - 1,
            0
        );

        liquidity = belowPriceLiquidity + abovePriceLiquidity;
        require(liquidity > 0, ZeroLiquidity());

        bytes[] memory temporaryParams = new bytes[](4);
        uint8 positionsToMint;

        uint256 protocolLockerBelowPriceLiquidity = isNoOpGovernance ? belowPriceLiquidity : belowPriceLiquidity / 10;

        if (protocolLockerBelowPriceLiquidity > 0) {
            temporaryParams[positionsToMint++] = abi.encode(
                poolKey,
                lowerTick,
                currentTick - poolKey.tickSpacing,
                protocolLockerBelowPriceLiquidity,
                0,
                balance1,
                address(this),
                new bytes(0)
            );
        }

        uint256 protocolLockerAbovePriceLiquidity = isNoOpGovernance ? abovePriceLiquidity : abovePriceLiquidity / 10;

        if (protocolLockerAbovePriceLiquidity > 0) {
            temporaryParams[positionsToMint++] = abi.encode(
                poolKey,
                currentTick + poolKey.tickSpacing,
                upperTick,
                protocolLockerAbovePriceLiquidity,
                balance0,
                0,
                address(this),
                new bytes(0)
            );
        }

        uint256 recipientBelowPriceLiquidity =
            isNoOpGovernance ? 0 : belowPriceLiquidity - protocolLockerBelowPriceLiquidity;

        if (recipientBelowPriceLiquidity > 0) {
            temporaryParams[positionsToMint++] = abi.encode(
                poolKey,
                lowerTick,
                currentTick - poolKey.tickSpacing,
                recipientBelowPriceLiquidity,
                0,
                balance1,
                recipient,
                new bytes(0)
            );
        }

        uint256 recipientAbovePriceLiquidity =
            isNoOpGovernance ? 0 : abovePriceLiquidity - protocolLockerAbovePriceLiquidity;

        if (recipientAbovePriceLiquidity > 0) {
            temporaryParams[positionsToMint++] = abi.encode(
                poolKey,
                currentTick + poolKey.tickSpacing,
                upperTick,
                recipientAbovePriceLiquidity,
                balance0,
                0,
                recipient,
                new bytes(0)
            );
        }

        uint8 length = positionsToMint + 1 + (token0 == address(0) ? 1 : 0);
        bytes[] memory params = new bytes[](length);
        bytes memory actions = new bytes(length);

        for (uint256 i; i < positionsToMint; ++i) {
            params[i] = temporaryParams[i];
            actions[i] = bytes1(uint8(Actions.MINT_POSITION));
        }

        actions[positionsToMint] = bytes1(uint8(Actions.SETTLE_PAIR));
        params[positionsToMint] = abi.encode(poolKey.currency0, poolKey.currency1);

        if (token0 == address(0)) {
            actions[length - 1] = bytes1(uint8(Actions.SWEEP));
            params[length - 1] = abi.encode(CurrencyLibrary.ADDRESS_ZERO, address(this));
        } else {
            ERC20(token0).approve(address(positionManager.permit2()), balance0);
            positionManager.permit2().approve(token0, address(positionManager), uint160(balance0), type(uint48).max);
        }

        ERC20(token1).approve(address(positionManager.permit2()), balance1);
        positionManager.permit2().approve(token1, address(positionManager), uint160(balance1), type(uint48).max);

        uint256 nextTokenId = positionManager.nextTokenId();

        positionManager.modifyLiquidities{ value: token0 == address(0) ? balance0 : 0 }(
            abi.encode(abi.encodePacked(actions), params), block.timestamp
        );

        if (protocolLockerBelowPriceLiquidity > 0) {
            positionManager.safeTransferFrom(
                address(this),
                locker,
                nextTokenId,
                abi.encode(recipient, plan.lockDuration, plan.beneficiaries)
            );
            nextTokenId++;
        }

        if (protocolLockerAbovePriceLiquidity > 0) {
            positionManager.safeTransferFrom(
                address(this),
                locker,
                nextTokenId,
                abi.encode(recipient, plan.lockDuration, plan.beneficiaries)
            );
        }

        address dustRecipient = isNoOpGovernance ? _protocolOwner() : recipient;
        if (poolKey.currency0.balanceOfSelf() > 0) {
            poolKey.currency0.transfer(dustRecipient, poolKey.currency0.balanceOfSelf());
        }
        if (poolKey.currency1.balanceOfSelf() > 0) {
            poolKey.currency1.transfer(dustRecipient, poolKey.currency1.balanceOfSelf());
        }

        emit V4PoolMigrated(poolKey.toId(), sqrtPriceX96, lowerTick, upperTick, liquidity, balance0, balance1);
    }

    function _storeBeneficiaryNoOp(PoolId, BeneficiaryData memory) private pure { }
}
