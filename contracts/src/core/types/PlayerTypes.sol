// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Club, Position } from "@core/types/AssetTypes.sol";

enum PlayerStatus { Inactive, Pending, Active }

struct Player {
    address tokenAddress;
    uint256 playerId;
    string name;
    string shortName;
    Club club;
    Position position;
    uint256 birthDate;
    uint256 seasonMinutes;
    PlayerStatus status;
}