// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { LimitOrderHook, OrderIdLibrary } from "@base/LimitOrderHook.sol";
import { ReentrancyGuardTransient } from "@oz/contracts/utils/ReentrancyGuardTransient.sol";
import { AddressBook } from "@base/AddressBook.sol";
import { DynamicFee } from "@base/DynamicFee.sol";

/**
 * @title MigratorHook | HighPotential
 * @author Isla Labs (Tom Jarvis | 0xBasti42)
 * @notice Post-migration hook for UniswapV4
 * @custom:experimental DeFi markets covering EPL, NFL, NBA, and more. | Learn more at https://docs.highpotential.io/
 * @custom:security-contact security@islalabs.co
 */
contract MigratorHook is LimitOrderHook, ReentrancyGuardTransient, AddressBook, DynamicFee { }
