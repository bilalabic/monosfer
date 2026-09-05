// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ProtocolConfig} from "../../../src/v1/config/ProtocolConfig.sol";

/**
 * @notice The §48 "Initial Testnet Parameters" table, expressed as a single struct.
 * @dev Kept in one place so every test starts from the documented baseline and any
 *      drift between the spec table and the code shows up as a test change.
 */
library BaselineParams {
    function baseline() internal pure returns (ProtocolConfig.Params memory) {
        return ProtocolConfig.Params({
            protocolFeeBps: 200, // §48: 2%
            coverageBpsR1: 2_500, // §6: 25%
            coverageBpsR2: 6_000, // §6: 60%
            coverageBpsR3: 10_000, // §6: 100%
            maxActiveCustody: 1, // §9
            customerMaxActiveListings: 5, // §48
            juryFirstSize: 3, // §48
            juryAppeal1Size: 5, // §48
            juryAppeal2Size: 7, // §48
            fundingWindow: 15 minutes, // §48
            challengeWindow: 24 hours, // §48
            courierWithdrawalCooldown: 24 hours, // §48
            riskQuoteValidity: 5 minutes, // §48
            podAttestationValidity: 10 minutes, // §48
            rewardClaimWindow: 90 days, // §48
            rewardReclaimDelay: 7 days, // §48
            courierBaseDeposit: 10 ether, // §48: 10 MON
            minJurorStake: 10 ether, // §48: 10 MON
            jurorLockPerCase: 2 ether, // §48: 2 MON
            nonRevealSlash: 1 ether // §48: 1 MON
        });
    }
}
