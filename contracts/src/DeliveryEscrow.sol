// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20Like {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface ILeaderboardLike {
    function recordDelivery(address courier, uint256 deliveryDurationSec, uint256 expectedDurationSec) external;
    function updateCourierRating(address courier, uint8 stars) external;
}

contract DeliveryEscrow {
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
        bool rated;
    }

    struct Bid {
        uint256 amount;
        uint16 estimatedMinutes;
        uint64 timestamp;
    }

    IERC20Like public immutable token;
    ILeaderboardLike public immutable leaderboard;
    address public immutable platformTreasury;
    address public immutable rewardPool;

    uint256 public constant MIN_COURIER_STAKE = 10 ether;
    uint256 public constant BID_DEPOSIT = 1 ether;
    uint256 public constant PLATFORM_FEE_BPS = 100; // %1

    uint256 public nextRequestId;

    mapping(uint256 => DeliveryRequest) public requests;
    mapping(uint256 => mapping(address => Bid)) public bids;
    mapping(uint256 => mapping(address => uint256)) public lockedBidDeposits;
    mapping(uint256 => address[]) public bidderList;
    mapping(address => bool) public isRegisteredCourier;
    mapping(address => uint256) public courierStake;

    event CourierRegistered(address indexed courier, uint256 stakeAmount);
    event StakeDeposited(address indexed courier, uint256 amount);
    event StakeWithdrawn(address indexed courier, uint256 amount);
    event DeliveryRequested(uint256 indexed requestId, address indexed customer, uint256 maxBudget, Urgency urgency);
    event BidSubmitted(uint256 indexed requestId, address indexed courier, uint256 amount);
    event CourierSelected(uint256 indexed requestId, address indexed courier, uint256 amount);
    event PickupConfirmed(uint256 indexed requestId, uint256 timestamp);
    event DeliveryConfirmed(uint256 indexed requestId, uint256 timestamp);
    event PaymentReleased(
        uint256 indexed requestId, address indexed courier, uint256 courierAmount, uint256 treasuryFee, uint256 rewardFee
    );
    event RatingSubmitted(uint256 indexed requestId, address indexed courier, uint8 stars);

    constructor(address tokenAddress, address leaderboardAddress, address treasuryAddress, address rewardPoolAddress) {
        require(tokenAddress != address(0), "Token zero");
        require(leaderboardAddress != address(0), "Leaderboard zero");
        require(treasuryAddress != address(0), "Treasury zero");
        require(rewardPoolAddress != address(0), "Reward zero");

        token = IERC20Like(tokenAddress);
        leaderboard = ILeaderboardLike(leaderboardAddress);
        platformTreasury = treasuryAddress;
        rewardPool = rewardPoolAddress;
    }

    function depositStake(uint256 amount) external {
        require(amount > 0, "Amount zero");
        _safeTransferFrom(msg.sender, address(this), amount);

        courierStake[msg.sender] += amount;
        if (!isRegisteredCourier[msg.sender] && courierStake[msg.sender] >= MIN_COURIER_STAKE) {
            isRegisteredCourier[msg.sender] = true;
            emit CourierRegistered(msg.sender, courierStake[msg.sender]);
        }
        emit StakeDeposited(msg.sender, amount);
    }

    function withdrawStake(uint256 amount) external {
        require(amount > 0, "Amount zero");
        uint256 stake = courierStake[msg.sender];
        require(stake >= amount, "Stake low");
        require(stake - amount >= MIN_COURIER_STAKE || !isRegisteredCourier[msg.sender], "Below min stake");

        courierStake[msg.sender] = stake - amount;
        _safeTransfer(msg.sender, amount);
        emit StakeWithdrawn(msg.sender, amount);
    }

    function createDeliveryRequest(
        bytes32 pickupHash,
        bytes32 deliveryHash,
        Urgency urgency,
        uint256 maxBudget
    ) external returns (uint256 requestId) {
        require(maxBudget > 0, "Budget zero");
        _safeTransferFrom(msg.sender, address(this), maxBudget);

        requestId = nextRequestId++;
        requests[requestId] = DeliveryRequest({
            customer: msg.sender,
            acceptedCourier: address(0),
            maxBudget: maxBudget,
            acceptedAmount: 0,
            createdAt: uint64(block.timestamp),
            pickupAt: 0,
            deliveredAt: 0,
            status: Status.OpenForBids,
            urgency: urgency,
            pickupHash: pickupHash,
            deliveryHash: deliveryHash,
            rated: false
        });

        emit DeliveryRequested(requestId, msg.sender, maxBudget, urgency);
    }

    function submitBid(uint256 requestId, uint256 bidAmount, uint16 estimatedMinutes) external {
        require(isRegisteredCourier[msg.sender], "Not courier");
        require(courierStake[msg.sender] >= BID_DEPOSIT, "Stake low");

        DeliveryRequest storage req = requests[requestId];
        require(req.status == Status.OpenForBids, "Not open");
        require(bidAmount > 0 && bidAmount <= req.maxBudget, "Invalid bid");
        require(bids[requestId][msg.sender].amount == 0, "Already bid");

        courierStake[msg.sender] -= BID_DEPOSIT;
        lockedBidDeposits[requestId][msg.sender] = BID_DEPOSIT;

        bids[requestId][msg.sender] =
            Bid({amount: bidAmount, estimatedMinutes: estimatedMinutes, timestamp: uint64(block.timestamp)});
        bidderList[requestId].push(msg.sender);

        emit BidSubmitted(requestId, msg.sender, bidAmount);
    }

    function acceptBid(uint256 requestId, address selectedCourier) external {
        DeliveryRequest storage req = requests[requestId];
        require(msg.sender == req.customer, "Not customer");
        require(req.status == Status.OpenForBids, "Wrong status");

        Bid memory selectedBid = bids[requestId][selectedCourier];
        require(selectedBid.amount > 0, "Bid not found");

        req.acceptedCourier = selectedCourier;
        req.acceptedAmount = selectedBid.amount;
        req.status = Status.Accepted;

        _refundNonSelectedDeposits(requestId, selectedCourier);

        uint256 refund = req.maxBudget - selectedBid.amount;
        if (refund > 0) {
            _safeTransfer(req.customer, refund);
        }

        emit CourierSelected(requestId, selectedCourier, selectedBid.amount);
    }

    function confirmPickup(uint256 requestId) external {
        DeliveryRequest storage req = requests[requestId];
        require(req.status == Status.Accepted, "Wrong status");
        require(msg.sender == req.acceptedCourier, "Not courier");

        req.status = Status.InTransit;
        req.pickupAt = uint64(block.timestamp);

        emit PickupConfirmed(requestId, block.timestamp);
    }

    function confirmDelivery(uint256 requestId) external {
        DeliveryRequest storage req = requests[requestId];
        require(req.status == Status.InTransit, "Wrong status");
        require(msg.sender == req.customer, "Not customer");

        req.status = Status.Delivered;
        req.deliveredAt = uint64(block.timestamp);

        _releasePayment(requestId);
        emit DeliveryConfirmed(requestId, block.timestamp);
    }

    function submitRating(uint256 requestId, uint8 stars) external {
        DeliveryRequest storage req = requests[requestId];
        require(msg.sender == req.customer, "Not customer");
        require(req.status == Status.Delivered, "Not delivered");
        require(!req.rated, "Already rated");
        require(stars >= 1 && stars <= 5, "Stars invalid");

        req.rated = true;
        leaderboard.updateCourierRating(req.acceptedCourier, stars);
        emit RatingSubmitted(requestId, req.acceptedCourier, stars);
    }

    function _releasePayment(uint256 requestId) internal {
        DeliveryRequest storage req = requests[requestId];
        uint256 totalAmount = req.acceptedAmount;

        uint256 platformFee = (totalAmount * PLATFORM_FEE_BPS) / 10000;
        uint256 rewardFee = platformFee / 2;
        uint256 treasuryFee = platformFee - rewardFee;
        uint256 courierNet = totalAmount - platformFee;

        _safeTransfer(req.acceptedCourier, courierNet);
        _safeTransfer(platformTreasury, treasuryFee);
        _safeTransfer(rewardPool, rewardFee);

        uint256 locked = lockedBidDeposits[requestId][req.acceptedCourier];
        if (locked > 0) {
            lockedBidDeposits[requestId][req.acceptedCourier] = 0;
            courierStake[req.acceptedCourier] += locked;
        }

        uint256 expectedDuration = _expectedDuration(req.urgency);
        uint256 actualDuration = req.deliveredAt - req.pickupAt;
        leaderboard.recordDelivery(req.acceptedCourier, actualDuration, expectedDuration);

        emit PaymentReleased(requestId, req.acceptedCourier, courierNet, treasuryFee, rewardFee);
    }

    function _refundNonSelectedDeposits(uint256 requestId, address selectedCourier) internal {
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

    function _expectedDuration(Urgency urgency) internal pure returns (uint256) {
        if (urgency == Urgency.Instant) return 30 minutes;
        if (urgency == Urgency.Express) return 1 hours;
        return 2 hours;
    }

    function _safeTransfer(address to, uint256 amount) internal {
        (bool ok, bytes memory data) = address(token).call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "Transfer failed");
    }

    function _safeTransferFrom(address from, address to, uint256 amount) internal {
        (bool ok, bytes memory data) =
            address(token).call(abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "TransferFrom failed");
    }
}
