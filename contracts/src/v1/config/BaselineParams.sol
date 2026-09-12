// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ProtocolConfig} from "./ProtocolConfig.sol";

/**
 * @title BaselineParams
 * @notice The sec. 48 "Initial Testnet Parameters" table, as the single source of truth.
 * @dev Lives in `src/` rather than `test/` because these are the values that
 *      actually get deployed. Both the deploy script and the test suite import
 *      this one library, so the parameters a test asserts against and the
 *      parameters a deployment ships cannot drift apart.
 *
 *      Baseline sec. 48 is a Testnet calibration table, not permanent Mainnet
 *      economics. Changing a value here changes what a fresh deployment starts
 *      with; existing deployments move only through ProtocolConfig's timelocked
 *      proposal path.
 */
library BaselineParams {
    function baseline() internal pure returns (ProtocolConfig.Params memory) {
        return ProtocolConfig.Params({
            protocolFeeBps: 200, // sec. 48: 2%
            coverageBpsR1: 2_500, // sec. 6: 25%
            coverageBpsR2: 6_000, // sec. 6: 60%
            coverageBpsR3: 10_000, // sec. 6: 100%
            coverageMultiplierMinBps: 7_500, // 0.75x — reputation discount floor
            coverageMultiplierMaxBps: 15_000, // 1.5x — risk surcharge ceiling
            maxActiveCustody: 1, // sec. 9
            customerMaxActiveListings: 5, // sec. 48
            juryFirstSize: 3, // sec. 48
            juryAppeal1Size: 5, // sec. 48
            juryAppeal2Size: 7, // sec. 48
            biddingWindow: 24 hours, // lifecycle window, not in sec. 48
            fundingWindow: 15 minutes, // sec. 48
            pickupWindow: 24 hours, // lifecycle window, not in sec. 48
            transitWindow: 72 hours, // lifecycle window, not in sec. 48
            returnWindow: 72 hours, // lifecycle window, not in sec. 48
            // sec. 20 wants the rating window bounded but names no figure; a week
            // is long enough for a customer to get round to it and short enough
            // that a rating still describes a delivery they remember.
            ratingWindow: 7 days,
            // sec. 28 gives the phases, not their lengths. Evidence gets the
            // longest window because gathering it happens off-chain and involves
            // people; the draw is a machine waiting on a provider; commit and
            // reveal are each a single transaction a juror has to remember to
            // send, so a day apiece.
            evidenceWindow: 3 days,
            drawWindow: 6 hours,
            commitWindow: 1 days,
            revealWindow: 1 days,
            appealWindow: 2 days,
            // Three full rounds plus three appeal windows come to 21.75 days;
            // 30 gives the court room without letting an escrow sit forever.
            disputeWindow: 30 days,
            challengeWindow: 24 hours, // sec. 48
            courierWithdrawalCooldown: 24 hours, // sec. 48
            riskQuoteValidity: 5 minutes, // sec. 48
            podAttestationValidity: 10 minutes, // sec. 48
            rewardClaimWindow: 90 days, // sec. 48
            rewardReclaimDelay: 7 days, // sec. 48
            courierBaseDeposit: 10 ether, // sec. 48: 10 MON
            minJurorStake: 10 ether, // sec. 48: 10 MON
            jurorLockPerCase: 2 ether, // sec. 48: 2 MON
            nonRevealSlash: 1 ether, // sec. 48: 1 MON
            arbitrationFeeFirst: 0.3 ether, // sec. 28
            arbitrationFeeAppeal1: 0.5 ether, // sec. 28
            arbitrationFeeAppeal2: 0.7 ether, // sec. 28
            disputeBondFirst: 1 ether, // sec. 28
            disputeBondAppeal1: 2 ether, // sec. 28
            disputeBondAppeal2: 4 ether // sec. 28
        });
    }
}
