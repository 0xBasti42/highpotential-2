// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { IPoolManager } from "@v4-core/interfaces/IPoolManager.sol";
import { TickMath } from "@v4-core/libraries/TickMath.sol";

function isTickSpacingValid(int24 tickSpacing) pure {
    require(tickSpacing <= TickMath.MAX_TICK_SPACING, IPoolManager.TickSpacingTooLarge(tickSpacing));
    require(tickSpacing >= TickMath.MIN_TICK_SPACING, IPoolManager.TickSpacingTooSmall(tickSpacing));
}
