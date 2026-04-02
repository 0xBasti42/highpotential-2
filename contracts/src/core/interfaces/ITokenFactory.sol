// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { CreateParams } from "@core/types/AssetTypes.sol";

interface ITokenFactory {
    function create(CreateParams calldata createData) external returns (address asset, bytes32 salt);
}
