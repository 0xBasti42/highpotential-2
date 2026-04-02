// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { ERC20 } from "@oz/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@oz/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { AccessControl } from "@core/AccessControl.sol";
import { PoolKey } from "@v4-core/types/PoolKey.sol";
import { Club, Position, TokenData } from "@core/types/AssetTypes.sol";

/**
 * @title HP20 | HighPotential
 * @author Isla Labs (Tom Jarvis | 0xBasti42)
 * @custom:experimental DeFi markets covering EPL, NFL, NBA, and more. | Learn more at https://docs.highpotential.io/
 * @custom:security-contact security@islalabs.co
 */
contract HP20 is ERC20, ERC20Permit, AccessControl {
    address constant PERMIT_2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // --------------------------------------------
    //  Metadata
    // --------------------------------------------

    uint256 public assetId;

    string public name;
    Club public club;
    Position public position;

    PoolKey public activePoolKey;
    bool public isPoolUnlocked;

    // --------------------------------------------
    //  Events and Errors
    // --------------------------------------------

    event ActivePoolKeySet(PoolKey key, bool locked);

    error PoolLocked();
    error PoolMustBeUnlocked();

    // --------------------------------------------
    //  Initialization
    // --------------------------------------------

    constructor(
        TokenData calldata tokenData,
        uint256 initialSupply,
        address recipient,
        address addressProvider_
    ) ERC20(tokenData.name, tokenData.symbol) ERC20Permit(tokenData.name) AccessControl(addressProvider_) {
        name = tokenData.name;
        club = tokenData.club;
        position = tokenData.position;

        _mint(recipient, initialSupply);
    }

    // --------------------------------------------
    //  ERC20 Extensions
    // --------------------------------------------

    function allowance(address owner, address spender) public view override returns (uint256) {
        if (spender == PERMIT_2) return type(uint256).max;
        return super.allowance(owner, spender);
    }

    function _update(address from, address to, uint256 value) internal override {
        address hook = address(activePoolKey.hooks);
        if (!isPoolUnlocked && hook != address(0) && to == hook) revert PoolLocked();
        super._update(from, to, value);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    // --------------------------------------------
    //  Pool Management
    // --------------------------------------------

    /// @notice Record the LBP / sale `PoolKey` and block ERC20 transfers into the hook until {unlockPool}.
    function lockActivePoolKey(PoolKey calldata key) external onlyInitializer {
        activePoolKey = key;
        isPoolUnlocked = false;
        emit ActivePoolKeySet(key, true);
    }

    function unlockPool() external onlyMigrator {
        isPoolUnlocked = true;
        emit ActivePoolKeySet(activePoolKey, false);
    }

    /// @notice Update `activePoolKey` after migration (requires pool unlocked; call after {unlockPool} in migrate flow).
    function syncActivePoolKey(PoolKey calldata key) external onlyMigrator {
        if (!isPoolUnlocked) revert PoolMustBeUnlocked();
        activePoolKey = key;
        emit ActivePoolKeySet(key, false);
    }
}
