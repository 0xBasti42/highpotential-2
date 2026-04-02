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

struct SeasonPosition {
    uint16 seasonStart;
    Position mainPosition;                      // most common position played over course of season
    PositionMinutes[] positionMinutes;          // tracks minutes played in each position over course of season
}

struct Player {
    address tokenAddress;                       // token address added during deployment
    uint256 playerId;                           // unique identifier calculated during initial store
    string fullName;                            // firstName lastName // fetched, filtered, updateable
    string shortName;                           // i.lastName // fetched, filtered, updateable
    Club club;                                  // fetched & updateable
    Position position;                          // most common position played over course of previous season
    SeasonPosition[] seasonPositions;           // tracks minutes played in each position over course of season
    uint256 birthDate;                          // unix timestamp // used to determine eligibility
    SeasonMinutes[] totalMinutes;               // minutes BTS // used to determine eligibility
    PlayerStatus status;                        // market status
}