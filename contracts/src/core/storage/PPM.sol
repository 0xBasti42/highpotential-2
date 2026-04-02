// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { AccessControl } from "@core/AccessControl.sol";
import { Oracle } from "@core/Oracle.sol";
import { RateLimit } from "@core/RateLimit.sol";
import { PPM } from "@core/types/PPMTypes.sol";
import { Errors } from "@core/libraries/EventsAndErrors.sol";

contract PPM is AccessControl, RateLimit, Oracle {
    bool public live;
    string public getPPMScript;

    constructor(address addressProvider_) AccessControl(addressProvider_) RateLimit(20 seconds) { }

    function scan() external rateLimited {
        if (!live) revert Errors.MatchweekNotLive();
        // TODO: Implement
    }

    function add(PPM memory ppm) external onlyOrchestrator {
        getPPM[ppm.token] = ppm;
        ppmCount++;
    }

    function remove(PPM memory ppm) external onlyOrchestrator {
        delete getPPM[ppm.token];
        ppmCount--;
    }
}