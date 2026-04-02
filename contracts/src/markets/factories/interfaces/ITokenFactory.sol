// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { CreateParams } from "@markets/types/Types.sol";

interface ITokenFactory {
    function create(
        CreateParams calldata createData,
        address addressProvider_
    ) external returns (address);
}
