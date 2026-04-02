// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { PoolId } from "@v4-core/types/PoolId.sol";
import { WAD } from "@markets/types/Wad.sol";

error UnorderedBeneficiaries();
error InvalidShares();
error InvalidProtocolOwnerBeneficiary();
error InvalidTotalShares();
error InvalidProtocolOwnerShares(uint96 required, uint96 provided);

uint96 constant MIN_PROTOCOL_OWNER_SHARES = uint96(WAD / 20);

struct BeneficiaryData {
    address beneficiary;
    uint96 shares;
}

function storeBeneficiaries(
    PoolId poolId,
    BeneficiaryData[] memory beneficiaries,
    address protocolOwner,
    uint96 protocolOwnerShares,
    function(PoolId, BeneficiaryData memory) storeBeneficiary
) {
    address prevBeneficiary;
    uint256 totalShares;
    bool foundProtocolOwner;

    for (uint256 i; i < beneficiaries.length; i++) {
        BeneficiaryData memory beneficiary = beneficiaries[i];

        require(prevBeneficiary < beneficiary.beneficiary, UnorderedBeneficiaries());
        require(beneficiary.shares > 0, InvalidShares());

        if (beneficiary.beneficiary == protocolOwner) {
            require(
                beneficiary.shares >= protocolOwnerShares,
                InvalidProtocolOwnerShares(protocolOwnerShares, beneficiary.shares)
            );
            foundProtocolOwner = true;
        }

        prevBeneficiary = beneficiary.beneficiary;
        totalShares += beneficiary.shares;

        if (PoolId.unwrap(poolId) != bytes32(0)) storeBeneficiary(poolId, beneficiary);
    }

    require(totalShares == WAD, InvalidTotalShares());
    require(foundProtocolOwner, InvalidProtocolOwnerBeneficiary());
}
