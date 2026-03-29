// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { ERC20 } from "@oz/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@oz/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { IAddressBook } from "@base/interfaces/IAddressBook.sol";

/**
 * @title HP20 | HighPotential
 * @author Isla Labs (Tom Jarvis | 0xBasti42)
 * @notice Fixed-supply player ERC20 with pool lock (LBP), immutable controller, and EIP-2612 permit.
 * @custom:experimental DeFi markets covering EPL, NFL, NBA, and more. | Learn more at https://docs.highpotential.io/
 * @custom:security-contact security@islalabs.co
 */
contract HP20 is ERC20Permit {
    address public immutable ADDRESS_BOOK;

    address constant PERMIT_2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // --------------------------------------------
    //  Configuration
    // --------------------------------------------

    address public pool;
    bool public isPoolUnlocked;

    // --------------------------------------------
    //  Events and Errors
    // --------------------------------------------

    error NoAddressBook();
    error InvalidAllocation();
    error InvalidBeneficiary();
    error Unauthorized();
    error PoolLocked();

    // --------------------------------------------
    //  Access Control
    // --------------------------------------------

    modifier onlyInitializer() {
        if (msg.sender != controller) revert Unauthorized();
        _;
    }

    modifier onlyMigrator() {
        if (msg.sender != controller) revert Unauthorized();
        _;
    }

    // --------------------------------------------
    //  Initialization
    // --------------------------------------------

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply,
        address recipient,
        address beneficiary,
        uint256 beneficiaryAmount,
        address addressBook_
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        if (addressBook_ == address(0)) revert NoAddressBook();

        ADDRESS_BOOK = addressBook_;

        if (beneficiaryAmount > initialSupply) revert InvalidAllocation();

        if (beneficiaryAmount != 0) {
            if (beneficiary == address(0)) revert InvalidBeneficiary();
            _mint(beneficiary, beneficiaryAmount);
        }

        _mint(recipient, initialSupply - beneficiaryAmount);
    }

    // --------------------------------------------
    //  Pool Management
    // --------------------------------------------

    function lockPool(
        address pool_
    ) external onlyInitializer {
        pool = pool_;
        isPoolUnlocked = false;
    }

    function unlockPool() external onlyMigrator {
        isPoolUnlocked = true;
    }

    // --------------------------------------------
    //  Asset Management
    // --------------------------------------------

    function burn(
        uint256 amount
    ) external {
        _burn(msg.sender, amount);
    }

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        if (to == pool && !isPoolUnlocked) revert PoolLocked();
        super._update(from, to, value);
    }

    function allowance(
        address owner,
        address spender
    ) public view override returns (uint256) {
        if (spender == PERMIT_2) return type(uint256).max;
        return super.allowance(owner, spender);
    }
}
