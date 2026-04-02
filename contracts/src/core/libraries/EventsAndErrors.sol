// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { ModuleState } from "@markets/Initializer.sol";
import { PoolData } from "@core/types/AssetTypes.sol";

library Events {
    event Create(address indexed asset, PoolData poolData);
    event Migrate(address indexed asset, PoolData poolData);
}

library Errors {
    error Unauthorized();
    error WrongModuleState(address module, ModuleState expected, ModuleState actual);
    error ArrayLengthsMismatch();
    error OracleNotConfigured();
    error EmptySource();
    error MatchweekNotLive();
    error RateLimited(uint256 nextAllowed);
    error ZeroCooldown();
}
