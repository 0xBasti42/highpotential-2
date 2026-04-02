// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IAddressProvider } from "@core/interfaces/IAddressProvider.sol";

abstract contract AccessControl {
    IAddressProvider public immutable addressProvider;

    // --------------------------------------------
    //  Config
    // --------------------------------------------

    enum ModuleState {
        NotWhitelisted,
        Orchestrator,
        Initializer,
        Migrator,
        Sunsetter
    }

    mapping(address module => ModuleState state) public whitelist;

    // --------------------------------------------
    //  Events / Errors
    // --------------------------------------------

    event Whitelisted(address indexed module, ModuleState indexed state);

    error CallerNotPermitted();
    error ArrayLengthsMismatch();
    error ZeroAddress();

    // --------------------------------------------
    //  Initialization
    // --------------------------------------------

    constructor(address _addressProvider) {
        addressProvider = IAddressProvider(_addressProvider);
        _setWhitelist();
    }

    // --------------------------------------------
    //  Main
    // --------------------------------------------

    modifier onlyOrchestrator() {
        if (whitelist[msg.sender] != ModuleState.Orchestrator) revert CallerNotPermitted();
        _;
    }

    modifier onlyInitializer() {
        if (whitelist[msg.sender] != ModuleState.Initializer) revert CallerNotPermitted();
        _;
    }

    modifier onlyMigrator() {
        if (whitelist[msg.sender] != ModuleState.Migrator) revert CallerNotPermitted();
        _;
    }

    modifier onlySunsetter() {
        if (whitelist[msg.sender] != ModuleState.Sunsetter) revert CallerNotPermitted();
        _;
    }
    
    // --------------------------------------------
    //  Whitelisting
    // --------------------------------------------

    function _setWhitelist() internal {
        string[] memory names = new string[](4);
        names[0] = "ORCHESTRATOR";
        names[1] = "INITIALIZER";
        names[2] = "MIGRATOR";
        names[3] = "SUNSETTER";

        address[] memory addrs = addressProvider.getManyByName(names);
        for (uint256 i; i < 4; ) {
            if (addrs[i] == address(0)) revert ZeroAddress();
            unchecked {
                ++i;
            }
        }

        ModuleState[] memory states_ = new ModuleState[](4);
        states_[0] = ModuleState.Orchestrator;
        states_[1] = ModuleState.Initializer;
        states_[2] = ModuleState.Migrator;
        states_[3] = ModuleState.Sunsetter;

        _setWhitelistState(addrs, states_);
    }

    function _setWhitelistState(address[] memory modules, ModuleState[] memory states) internal {
        uint256 length = modules.length;

        if (length != states.length) {
            revert ArrayLengthsMismatch();
        }

        for (uint256 i; i < length; ++i) {
            whitelist[modules[i]] = states[i];
            emit Whitelisted(modules[i], states[i]);
        }
    }

    // --------------------------------------------
    //  External View
    // --------------------------------------------

    function checkModuleState(address module, ModuleState state) external view returns (bool) {
        return whitelist[module] == state;
    }
}
