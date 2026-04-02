// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Club, Position } from "@core/types/AssetTypes.sol";

enum PlayerStatus { Inactive, Pending, Active }

struct SeasonMinutes {
    uint16 seasonStart;
    uint256 seasonMinutes;
}

struct PositionMinutes {
    Position position;
    uint256 positionMinutes;
}

struct Player {
    address tokenAddress;                       // token address added during deployment
    uint256 playerId;                           // unique identifier calculated during initial store
    string fullName;                            // firstName lastName // fetched, filtered, updateable
    string shortName;                           // i.lastName // fetched, filtered, updateable
    Club club;                                  // fetched & updateable
    Position position;                          // denominated from most common position
    PositionMinutes[] positionMinutes;          // tracks minutes played in each position
    uint256 birthDate;                          // unix timestamp // used to determine eligibility
    SeasonMinutes[] totalMinutes;               // minutes BTS // used to determine eligibility
    PlayerStatus status;                        // market status
}