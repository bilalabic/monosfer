// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReputationBadge} from "./ReputationBadge.sol";

contract Leaderboard {
    struct CourierStats {
        uint32 totalDeliveries;
        uint32 onTimeCount;
        uint32 lateCount;
        uint32 totalRatingSum;
        uint256 score;
        uint64 lastUpdate;
    }

    address public owner;
    address public escrowContract;
    ReputationBadge public immutable badge;

    mapping(address => CourierStats) public courierStats;

    event EscrowContractUpdated(address indexed escrow);
    event ScoreUpdated(address indexed courier, uint256 newScore, uint256 timestamp);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyEscrow() {
        require(msg.sender == escrowContract, "Not escrow");
        _;
    }

    constructor(address initialOwner, address badgeAddress) {
        require(initialOwner != address(0), "Owner zero");
        require(badgeAddress != address(0), "Badge zero");
        owner = initialOwner;
        badge = ReputationBadge(badgeAddress);
    }

    function setEscrowContract(address newEscrow) external onlyOwner {
        require(newEscrow != address(0), "Escrow zero");
        escrowContract = newEscrow;
        emit EscrowContractUpdated(newEscrow);
    }

    function recordDelivery(address courier, uint256 deliveryDurationSec, uint256 expectedDurationSec) external onlyEscrow {
        CourierStats storage stats = courierStats[courier];
        stats.totalDeliveries += 1;
        if (deliveryDurationSec <= expectedDurationSec) stats.onTimeCount += 1;
        else stats.lateCount += 1;

        _recalculateScore(courier);

        if (stats.totalDeliveries == 1) {
            badge.mint(courier, ReputationBadge.BadgeType.FirstDelivery);
        }
    }

    function updateCourierRating(address courier, uint8 stars) external onlyEscrow {
        require(stars >= 1 && stars <= 5, "Stars invalid");
        CourierStats storage stats = courierStats[courier];
        stats.totalRatingSum += stars;
        _recalculateScore(courier);
    }

    function getAverageRatingBps(address courier) external view returns (uint256) {
        CourierStats memory stats = courierStats[courier];
        if (stats.totalDeliveries == 0) return 0;
        return (uint256(stats.totalRatingSum) * 100) / uint256(stats.totalDeliveries);
    }

    function getTopCouriers(address[] calldata candidates, uint256 topN)
        external
        view
        returns (address[] memory couriers, uint256[] memory scores)
    {
        uint256 n = candidates.length < topN ? candidates.length : topN;
        couriers = new address[](n);
        scores = new uint256[](n);

        address[] memory sorted = candidates;
        for (uint256 i = 0; i < sorted.length; i++) {
            for (uint256 j = i + 1; j < sorted.length; j++) {
                if (courierStats[sorted[j]].score > courierStats[sorted[i]].score) {
                    address temp = sorted[i];
                    sorted[i] = sorted[j];
                    sorted[j] = temp;
                }
            }
        }

        for (uint256 i = 0; i < n; i++) {
            couriers[i] = sorted[i];
            scores[i] = courierStats[sorted[i]].score;
        }
    }

    function _recalculateScore(address courier) internal {
        CourierStats storage s = courierStats[courier];
        if (s.totalDeliveries == 0) {
            s.score = 0;
            s.lastUpdate = uint64(block.timestamp);
            emit ScoreUpdated(courier, 0, block.timestamp);
            return;
        }

        uint256 deliveryPoints = uint256(s.totalDeliveries) * 10;
        uint256 onTimeRatio = (uint256(s.onTimeCount) * 100) / uint256(s.totalDeliveries);
        uint256 onTimePoints = (onTimeRatio * 50) / 100;
        uint256 ratingPoints = (uint256(s.totalRatingSum) * 20) / uint256(s.totalDeliveries);
        uint256 penalty = uint256(s.lateCount) * 8;
        uint256 total = deliveryPoints + onTimePoints + ratingPoints;

        s.score = total > penalty ? total - penalty : 0;
        s.lastUpdate = uint64(block.timestamp);
        emit ScoreUpdated(courier, s.score, block.timestamp);
    }
}
