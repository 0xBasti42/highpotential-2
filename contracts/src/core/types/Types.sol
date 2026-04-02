// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { IPoolInitializer } from "@core/interfaces/IPoolInitializer.sol";
import { PoolKey } from "@v4-core/types/PoolKey.sol";

struct Asset {
    address token;
    PoolData poolData;
    address positionTracker;
    address lpStore;
    uint256 activatedAt;
    bool hasMigrated;
    address vault;
    address stToken;
	address cToken;
	address vcToken;
    uint256 deactivatedAt;
    bool hasRedistributed;
}

struct CreateParams {
    string name;
    string symbol;
    string tokenURI;
    bytes32 metadataHash;
    bytes32 salt;
}

struct PoolData {
    address numeraire;
    PoolKey activePool;
    address hookDoppler;
    uint256 hookMigrator;
}

struct Share {
    address beneficiary;    // Advanced trade beacon or PlayerVault aggregator || PBRTreasury or FRTreasury
    uint16 shareBps;      // e.g. 6600 (= 66%), 3400 (= 34%) || 8900 (= 89%), 1100 (= 11%); staker gets 10_000 - positionBps.
}