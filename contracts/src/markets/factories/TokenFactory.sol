// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import { AccessControl } from "@core/AccessControl.sol";
import { AddressBook } from "@core/AddressBook.sol";
import { HP20 } from "@markets/tokens/HP20.sol";
import { CreateParams, TokenData } from "@core/types/AssetTypes.sol";
import { DopplerConfig as DC } from "@core/libraries/DopplerConfig.sol";

contract TokenFactory is AccessControl, AddressBook {
    constructor(address addressProvider_) AccessControl(addressProvider_) AddressBook(addressProvider_) { }

    function create(CreateParams calldata createData) external onlyInitializer returns (address asset, bytes32 salt) {
        TokenData memory tokenData = createData.tokenData;
        bytes32 salt_ = createData.salt;

        asset = address(
            new HP20{ salt: salt_ }(
                tokenData,
                DC.TOTAL_SUPPLY,
                msg.sender,
                address(addressProvider)
            )
        );

        return (asset, salt_);
    }
}
