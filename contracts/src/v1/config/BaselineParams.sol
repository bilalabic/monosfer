// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ProtocolConfig} from "./ProtocolConfig.sol";

/**
 * @title BaselineParams
 * @notice The §48 "Initial Testnet Parameters" table, as the single source of truth.
 * @dev Lives in `src/` rather than `test/` because these are the values that
 *      actually get deployed. Both the deploy script and the test suite import
 *      this one library, so the parameters a test asserts against and the
 *      parameters a deployment ships cannot drift apart.
 *
 *      Baseline §48 is a Testnet calibration table, not permanent Mainnet
 *      economics. Changing a value here changes what a fresh deployment starts
 *      with; existing deployments move only through ProtocolConfig's timelocked
 *      proposal path.
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
