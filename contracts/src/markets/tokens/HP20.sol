// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { ERC20 } from "@oz/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@oz/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { PoolKey } from "@v4-core/types/PoolKey.sol";
import { IAddressProvider } from "@base/interfaces/IAddressProvider.sol";
import { Share } from "@markets/types/Types.sol";
import { AvgPosition, Coefficients } from "@markets/types/PPMTypes.sol";

/**
 * @title HP20 | HighPotential
 * @author Isla Labs (Tom Jarvis | 0xBasti42)
 * @notice Fixed-supply player token with Uniswap v4 `PoolKey` tracking, LBP hook lock, EIP-2612 permit, and URI metadata.
 * @dev Register on `ADDRESS_PROVIDER`: `PERMIT_2`, `INITIALIZER`, `MIGRATOR`, `METADATA_ADMIN` (updates URI / hash).
 * @custom:experimental DeFi markets covering EPL, NFL, NBA, and more. | Learn more at https://docs.highpotential.io/
 * @custom:security-contact security@islalabs.co
 */
contract HP20 is ERC20, ERC20Permit {
    address constant PERMIT_2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    address public initializer;
    address public migrator;
    address public orchestrator;

    // --------------------------------------------
    //  Metadata
    // --------------------------------------------

    string public name;
    string public symbol;
    string public tokenURI;
    bytes32 public metadataHash;

    PoolKey public activePoolKey;

    bool public isPoolUnlocked;

    // --------------------------------------------
    //  Storage
    // --------------------------------------------

    struct PPM {
        address vault;
        Coefficients coefficients;
        uint256 prevTotal;
        uint256 latestTotal;
    }

    // --------------------------------------------
    //  Events and Errors
    // --------------------------------------------

    event ActivePoolKeySet(PoolKey key, bool locked);
    event TokenURIUpdated(string newURI);
    event MetadataHashUpdated(bytes32 newHash);

    error NoAddressBook();
    error InvalidAllocation();
    error InvalidBeneficiary();
    error Unauthorized();
    error PoolLocked();
    error PoolMustBeUnlocked();

    // --------------------------------------------
    //  Access Control
    // --------------------------------------------

    modifier onlyAdmin() {
        if (msg.sender != initializer || msg.sender != migrator || msg.sender != orchestrator) revert Unauthorized();
        _;
    }

    // --------------------------------------------
    //  Initialization
    // --------------------------------------------

    constructor(
        string memory name_,
        string memory symbol_,
        string memory tokenURI_,
        bytes32 metadataHash_,
        uint256 initialSupply,
        address recipient,
        address addressProvider_
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        if (addressProvider_ == address(0)) revert NoAddressBook();
        IAddressProvider addressProvider = IAddressProvider(address(addressProvider_));

        tokenURI = tokenURI_;
        metadataHash = metadataHash_;

        initializer = addressProvider.getAddress("INITIALIZER");
        migrator = addressProvider.getAddress("MIGRATOR");
        orchestrator = addressProvider.getAddress("ORCHESTRATOR");
        permit2 = addressProvider.getAddress("PERMIT_2");

        _mint(recipient, initialSupply);
    }

    // --------------------------------------------
    //  ERC20 Extensions
    // --------------------------------------------

    function allowance(address owner, address spender) public view override returns (uint256) {
        if (spender == IAddressProvider(ADDRESS_PROVIDER).getByName("PERMIT_2")) return type(uint256).max;
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
    //  Update Metadata
    // --------------------------------------------

    function setTokenURI(string calldata newURI) external onlyAdmin {
        tokenURI = newURI;
        emit TokenURIUpdated(newURI);
    }

    function setMetadataHash(bytes32 newHash) external onlyAdmin {
        metadataHash = newHash;
        emit MetadataHashUpdated(newHash);
    }

    // --------------------------------------------
    //  Pool Management
    // --------------------------------------------

    /// @notice Record the LBP / sale `PoolKey` and block ERC20 transfers into the hook until {unlockPool}.
    function lockActivePoolKey(PoolKey calldata key) external onlyAdmin {
        activePoolKey = key;
        isPoolUnlocked = false;
        emit ActivePoolKeySet(key, true);
    }

    function unlockPool() external onlyAdmin {
        isPoolUnlocked = true;
        emit ActivePoolKeySet(activePoolKey, false);
    }

    /// @notice Update `activePoolKey` after migration (requires pool unlocked; call after {unlockPool} in migrate flow).
    function syncActivePoolKey(PoolKey calldata key) external onlyAdmin {
        if (!isPoolUnlocked) revert PoolMustBeUnlocked();
        activePoolKey = key;
        emit ActivePoolKeySet(key, false);
    }
}
