// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.34;

import { IPoolManager } from "@v4-core/PoolManager.sol";
import { Doppler } from "@doppler/initializers/Doppler.sol";
import { StandardizedBondingCurve } from "@markets/StandardizedBondingCurve.sol";

/**
 * @title DopplerFactory | HighPotential
 * @author Isla Labs (Tom Jarvis | 0xBasti42)
 * @notice Standalone CREATE2 deployer for the canonical bonding curve (same encoding as `Initializer` + `DopplerDeployer`)
 * @custom:experimental DeFi markets covering EPL, NFL, NBA, and more. | Learn more at https://docs.highpotential.io/
 * @custom:security-contact security@islalabs.co
 */
contract DopplerFactory {
    IPoolManager public poolManager;

    constructor(IPoolManager poolManager_) {
        poolManager = poolManager_;
    }

    /// @param salt CREATE2 salt chosen by the caller (e.g. `keccak256(abi.encode("HP:Doppler", asset, factory, chainid, nonce))`)
    function deploy(bytes32 salt) external returns (Doppler) {
        uint256 saleStart = block.timestamp + StandardizedBondingCurve.SALE_DELAY;
        uint256 saleEnd = saleStart + StandardizedBondingCurve.SALE_DURATION;
        bytes memory data = StandardizedBondingCurve.dopplerInitPayload(saleStart, saleEnd);

        (
            uint256 minimumProceeds,
            uint256 maximumProceeds,
            uint256 startingTime,
            uint256 endingTime,
            int24 startingTick,
            int24 endingTick,
            uint256 epochLength,
            int24 gamma,
            bool isToken0,
            uint256 numPDSlugs,
            uint24 lpFee,
        ) = abi.decode(
            data, (uint256, uint256, uint256, uint256, int24, int24, uint256, int24, bool, uint256, uint24, int24)
        );

        return new Doppler{ salt: salt }(
            poolManager,
            StandardizedBondingCurve.TOKENS_TO_SELL,
            minimumProceeds,
            maximumProceeds,
            startingTime,
            endingTime,
            startingTick,
            endingTick,
            epochLength,
            gamma,
            isToken0,
            numPDSlugs,
            msg.sender,
            lpFee
        );
    }
}
