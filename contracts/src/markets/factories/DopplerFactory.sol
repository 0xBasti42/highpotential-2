// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { AccessControl } from "@core/AccessControl.sol";
import { AddressBook } from "@core/AddressBook.sol";
import { IPoolManager } from "@v4-core/PoolManager.sol";
import { DopplerHook } from "@markets/hooks/DopplerHook.sol";
import { DopplerConfig as DC } from "@core/libraries/DopplerConfig.sol";

contract DopplerFactory is AccessControl, AddressBook {
    constructor(address addressProvider_) AccessControl(addressProvider_) AddressBook(addressProvider_) { }

    function deploy(bytes32 salt) external onlyInitializer returns (address dopplerHook) {
        address poolManager = _getAddress(_addressKey("POOL_MANAGER"));
        address initializer = _getAddress(_addressKey("INITIALIZER"));

        DopplerHook hook = new DopplerHook{ salt: salt }(
            IPoolManager(poolManager),
            DC.NUM_TOKENS_TO_SELL,
            DC.MINIMUM_PROCEEDS,
            DC.MAXIMUM_PROCEEDS,
            DC.STARTING_TIME,
            DC.ENDING_TIME,
            DC.STARTING_TICK,
            DC.ENDING_TICK,
            DC.EPOCH_LENGTH,
            DC.GAMMA,
            DC.IS_TOKEN0,
            DC.NUM_PD_SLUGS,
            initializer,
            DC.LP_FEE
        );

        return address(hook);
    }
}
