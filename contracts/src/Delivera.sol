// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Delivera — Crowdsourced Kurye Pazaryeri (Hackathon MVP)
 * @notice Native MON kullanir, ERC20 gerektirmez. Leaderboard dahili.
 * @dev Hackathon icin sade versiyon. Production icin dispute, oracle ve ek guvenlikler gerekir.
 */
contract Delivera {
    enum Status {
        OpenForBids,
        Accepted,
        InTransit,
        Delivered,
        Cancelled
    }

    enum Urgency {
        Standard,
        Express,
        Instant
    }

    struct DeliveryRequest {
        address customer;
        address acceptedCourier;
        uint256 maxBudget;
        uint256 acceptedAmount;
        uint64 createdAt;
        uint64 pickupAt;
        uint64 deliveredAt;
        Status status;
        Urgency urgency;
        bytes32 pickupHash;
        bytes32 deliveryHash;
        uint8 rating;
        bool rated;
    }

    struct Bid {
        uint256 amount;
        uint16 estimatedMinutes;
        uint64 timestamp;
    }

    struct CourierStats {
        uint32 totalDeliveries;
        uint32 totalRatingSum;
        uint32 onTimeCount;
        uint32 lateCount;
        uint256 leaderboardScore;
        uint64 joinedAt;
    }

    mapping(uint256 => DeliveryRequest) public requests;
    mapping(uint256 => mapping(address => Bid)) public bids;
    mapping(uint256 => mapping(address => uint256)) public lockedBidDeposits;
    mapping(uint256 => address[]) public bidderList;
    mapping(address => CourierStats) public courierStats;
    mapping(address => bool) public isRegisteredCourier;
    mapping(address => uint256) public courierStake;

    address[] public allCouriers;
    uint256 public nextRequestId;

    uint256 public constant MIN_COURIER_STAKE = 0.01 ether;
    uint256 public constant BID_DEPOSIT = 0.001 ether;
    uint256 public constant PLATFORM_FEE_BPS = 100; // %1

    address public immutable platformTreasury;
    address public immutable rewardPool;

    event DeliveryRequested(uint256 indexed requestId, address indexed customer, uint256 maxBudget, Urgency urgency);
    event BidSubmitted(uint256 indexed requestId, address indexed courier, uint256 amount);
    event CourierSelected(uint256 indexed requestId, address indexed courier, uint256 amount);
    event PickupConfirmed(uint256 indexed requestId, uint256 timestamp);
    event DeliveryConfirmed(uint256 indexed requestId, uint256 timestamp);
    event PaymentReleased(uint256 indexed requestId, address indexed courier, uint256 courierAmount);
    event RatingSubmitted(uint256 indexed requestId, address indexed courier, uint8 stars);
    event ScoreUpdated(address indexed courier, uint256 newScore);

    constructor(address _platformTreasury, address _rewardPool) {
        require(_platformTreasury != address(0), "Treasury zero");
        require(_rewardPool != address(0), "Reward pool zero");
        platformTreasury = _platformTreasury;
        rewardPool = _rewardPool;
    }

    function registerCourier() external payable {
        require(!isRegisteredCourier[msg.sender], "Already registered");
        require(msg.value >= MIN_COURIER_STAKE, "Insufficient stake");

        isRegisteredCourier[msg.sender] = true;
        courierStake[msg.sender] += msg.value;
        courierStats[msg.sender].joinedAt = uint64(block.timestamp);
        allCouriers.push(msg.sender);
    }

    function createDeliveryRequest(
        bytes32 pickupHash,
        bytes32 deliveryHash,
        Urgency urgency
    ) external payable returns (uint256 requestId) {
        require(msg.value > 0, "No budget");

        requestId = nextRequestId++;
        requests[requestId] = DeliveryRequest({
            customer: msg.sender,
            acceptedCourier: address(0),
            maxBudget: msg.value,
            acceptedAmount: 0,
            createdAt: uint64(block.timestamp),
            pickupAt: 0,
            deliveredAt: 0,
            status: Status.OpenForBids,
            urgency: urgency,
            pickupHash: pickupHash,
            deliveryHash: deliveryHash,
            rating: 0,
            rated: false
        });

        emit DeliveryRequested(requestId, msg.sender, msg.value, urgency);
    }

    function submitBid(uint256 requestId, uint256 bidAmount, uint16 estimatedMinutes) external {
        require(isRegisteredCourier[msg.sender], "Not registered courier");
        DeliveryRequest storage req = requests[requestId];
        require(req.status == Status.OpenForBids, "Not open");
        require(bidAmount > 0 && bidAmount <= req.maxBudget, "Invalid bid");
        require(bids[requestId][msg.sender].amount == 0, "Already bid");
        require(courierStake[msg.sender] >= BID_DEPOSIT, "Insufficient stake for bid");

        courierStake[msg.sender] -= BID_DEPOSIT;
        lockedBidDeposits[requestId][msg.sender] = BID_DEPOSIT;

        bids[requestId][msg.sender] = Bid({
            amount: bidAmount,
            estimatedMinutes: estimatedMinutes,
            timestamp: uint64(block.timestamp)
        });
        bidderList[requestId].push(msg.sender);

        emit BidSubmitted(requestId, msg.sender, bidAmount);
    }

    function acceptBid(uint256 requestId, address selectedCourier) external {
        DeliveryRequest storage req = requests[requestId];
        require(req.customer == msg.sender, "Not customer");
        require(req.status == Status.OpenForBids, "Wrong status");

        Bid memory bid = bids[requestId][selectedCourier];
        require(bid.amount > 0, "Bid not found");

        req.acceptedCourier = selectedCourier;
        req.acceptedAmount = bid.amount;
        req.status = Status.Accepted;

        _refundNonSelectedBidDeposits(requestId, selectedCourier);

        uint256 refund = req.maxBudget - bid.amount;
        if (refund > 0) {
            (bool ok, ) = msg.sender.call{value: refund}("");
            require(ok, "Refund failed");
        }

        emit CourierSelected(requestId, selectedCourier, bid.amount);
    }

    function confirmPickup(uint256 requestId) external {
        DeliveryRequest storage req = requests[requestId];
        require(req.acceptedCourier == msg.sender, "Not courier");
        require(req.status == Status.Accepted, "Wrong status");

        req.status = Status.InTransit;
        req.pickupAt = uint64(block.timestamp);

        emit PickupConfirmed(requestId, block.timestamp);
    }

    function confirmDelivery(uint256 requestId) external {
        DeliveryRequest storage req = requests[requestId];
        require(req.customer == msg.sender, "Not customer");
        require(req.status == Status.InTransit, "Wrong status");

        req.status = Status.Delivered;
        req.deliveredAt = uint64(block.timestamp);

        _releasePayment(requestId);
        emit DeliveryConfirmed(requestId, block.timestamp);
    }

    function _releasePayment(uint256 requestId) internal {
        DeliveryRequest storage req = requests[requestId];
        uint256 total = req.acceptedAmount;

        uint256 platformFee = (total * PLATFORM_FEE_BPS) / 10000;
        uint256 rewardPoolFee = platformFee / 2;
        uint256 treasuryFee = platformFee - rewardPoolFee;
        uint256 courierNet = total - platformFee;

        (bool okCourier, ) = req.acceptedCourier.call{value: courierNet}("");
        require(okCourier, "Courier payment failed");
        (bool okTreasury, ) = platformTreasury.call{value: treasuryFee}("");
        require(okTreasury, "Treasury transfer failed");
        (bool okReward, ) = rewardPool.call{value: rewardPoolFee}("");
        require(okReward, "Reward transfer failed");

        uint256 locked = lockedBidDeposits[requestId][req.acceptedCourier];
        if (locked > 0) {
            lockedBidDeposits[requestId][req.acceptedCourier] = 0;
            courierStake[req.acceptedCourier] += locked;
        }

        _updateCourierScore(req.acceptedCourier, requestId);
        emit PaymentReleased(requestId, req.acceptedCourier, courierNet);
    }

    function submitRating(uint256 requestId, uint8 stars) external {
        DeliveryRequest storage req = requests[requestId];
        require(req.customer == msg.sender, "Not customer");
        require(req.status == Status.Delivered, "Not delivered");
        require(!req.rated, "Already rated");
        require(stars >= 1 && stars <= 5, "Invalid stars");

        req.rated = true;
        req.rating = stars;

        CourierStats storage stats = courierStats[req.acceptedCourier];
        stats.totalRatingSum += stars;

        _recalculateScore(req.acceptedCourier);
        emit RatingSubmitted(requestId, req.acceptedCourier, stars);
    }

    function _refundNonSelectedBidDeposits(uint256 requestId, address selectedCourier) internal {
        address[] memory bidders = bidderList[requestId];
        for (uint256 i = 0; i < bidders.length; i++) {
            address bidder = bidders[i];
            if (bidder == selectedCourier) continue;

            uint256 locked = lockedBidDeposits[requestId][bidder];
            if (locked > 0) {
                lockedBidDeposits[requestId][bidder] = 0;
                courierStake[bidder] += locked;
            }
        }
    }

    function _updateCourierScore(address courier, uint256 requestId) internal {
        CourierStats storage stats = courierStats[courier];
        DeliveryRequest memory req = requests[requestId];

        stats.totalDeliveries += 1;
        uint256 expected = _expectedDuration(req.urgency);
        uint256 actual = req.deliveredAt - req.pickupAt;
        if (actual <= expected) stats.onTimeCount += 1;
        else stats.lateCount += 1;

        _recalculateScore(courier);
    }

    function _recalculateScore(address courier) internal {
        CourierStats storage s = courierStats[courier];
        if (s.totalDeliveries == 0) {
            s.leaderboardScore = 0;
            return;
        }

        uint256 deliveryPoints = uint256(s.totalDeliveries) * 10;
        uint256 onTimeRatio = (uint256(s.onTimeCount) * 100) / s.totalDeliveries;
        uint256 onTimePoints = (onTimeRatio * 50) / 100;
        uint256 avgRating = s.totalRatingSum == 0 ? 0 : (uint256(s.totalRatingSum) * 20) / s.totalDeliveries;
        uint256 penalty = uint256(s.lateCount) * 8;

        uint256 total = deliveryPoints + onTimePoints + avgRating;
        s.leaderboardScore = total > penalty ? total - penalty : 0;

        emit ScoreUpdated(courier, s.leaderboardScore);
    }

    function _expectedDuration(Urgency u) internal pure returns (uint256) {
        if (u == Urgency.Instant) return 30 minutes;
        if (u == Urgency.Express) return 1 hours;
        return 2 hours;
    }

    function getBidders(uint256 requestId) external view returns (address[] memory) {
        return bidderList[requestId];
    }

    function getAllCouriers() external view returns (address[] memory) {
        return allCouriers;
    }

    function getAverageRating(address courier) external view returns (uint256) {
        CourierStats memory s = courierStats[courier];
        if (s.totalDeliveries == 0) return 0;
        return (uint256(s.totalRatingSum) * 100) / s.totalDeliveries;
    }

    function getLeaderboard(uint256 topN) external view returns (address[] memory couriers, uint256[] memory scores) {
        uint256 n = allCouriers.length < topN ? allCouriers.length : topN;
        couriers = new address[](n);
        scores = new uint256[](n);

        address[] memory sorted = allCouriers;
        for (uint256 i = 0; i < sorted.length; i++) {
            for (uint256 j = i + 1; j < sorted.length; j++) {
                if (courierStats[sorted[j]].leaderboardScore > courierStats[sorted[i]].leaderboardScore) {
                    address temp = sorted[i];
                    sorted[i] = sorted[j];
                    sorted[j] = temp;
                }
            }
        }

        for (uint256 i = 0; i < n; i++) {
            couriers[i] = sorted[i];
            scores[i] = courierStats[sorted[i]].leaderboardScore;
        }
    }
}
