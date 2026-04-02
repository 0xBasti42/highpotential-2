// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import { ITokenFactory } from "@markets/factories/interfaces/ITokenFactory.sol";
import { AccessControl } from "@core/AccessControl.sol";
import { AddressBook } from "@core/AddressBook.sol";
import { HP20 } from "@markets/tokens/HP20.sol";
import { CreateParams } from "@core/types/Types.sol";
import { Errors } from "@core/libraries/Errors.sol";

contract TokenFactory is ITokenFactory, AccessControl, AddressBook {
    constructor(address addressProvider_) AccessControl(addressProvider_) AddressBook(addressProvider_) { }

    function create(
        uint256 totalSupply,
        CreateParams calldata createData
    ) external onlyInitializer returns (address asset, bytes32 salt) {
        ( string memory name, string memory symbol, string memory tokenURI, bytes32 metadataHash, bytes32 salt) = abi.decode(
            createData, (string, string, string, bytes32, bytes32)
        );

        address asset = address(
            new HP20{ salt: salt }(
                name,
                symbol,
                tokenURI,
                metadataHash,
                totalSupply,
                msg.sender,
                address(addressProvider)
            )
        );

        return (asset, salt);
    }
}
