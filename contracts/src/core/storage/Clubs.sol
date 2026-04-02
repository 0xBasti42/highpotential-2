// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { AccessControl } from "@core/AccessControl.sol";
import { Oracle } from "@core/Oracle.sol";
import { RateLimit } from "@core/RateLimit.sol";
import { Club } from "@core/types/AssetTypes.sol";

contract Clubs is AccessControl, RateLimit, Oracle {
    string public getClubsScript;
    uint256 public clubCount;

    mapping(string shorthand => Club club) public getClub;
    mapping(string shorthand => uint256 clubId) public getClubId;

    constructor(address addressProvider_) AccessControl(addressProvider_) RateLimit(24 hours) { }

    function scan() external rateLimited {
        // TODO: Implement
    }

    function add(Club memory club) external onlyOrchestrator {
        getClub[club.shorthand] = club;
        getClubId[club.shorthand] = club.clubId;
        clubCount++;
    }

    function remove(Club memory club) external onlyOrchestrator {
        delete getClub[club.shorthand];
        delete getClubId[club.shorthand];
        clubCount--;
    }
}