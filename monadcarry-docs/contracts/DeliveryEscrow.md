# DeliveryEscrow.sol — Ana Kontrat Spesifikasyonu

## Amaç

Teslimat akışının 01'den 06'ya kadar tüm adımlarını yöneten ana kontrat. Müşteri talebinden kuryeye ödeme yapılana kadar tüm state'i tutar.

## Struct'lar

```solidity
enum Status {
    OpenForBids,       // 01: Talep oluşturuldu, teklif bekliyor
    Accepted,          // 03: Kurye seçildi
    InTransit,         // 04: Kurye paketi aldı
    Delivered,         // 05: Teslim edildi
    Completed,         // 06: Ödeme yapıldı
    Cancelled,         // İptal
    Disputed,          // Anlaşmazlık sürüyor
    Failed             // Teslim edilemedi
}

enum Urgency {
    Standard,   // 2 saat
    Express,    // 1 saat
    Instant     // 30 dakika
}

enum PackageType {
    Document,
    Food,
    Small,
    Medium,
    Large
}

struct DeliveryRequest {
    address customer;
    address acceptedCourier;
    address recipientWallet;      // opsiyonel
    
    bytes32 pickupHash;
    bytes32 deliveryHash;
    bytes32 recipientCommitment;  // SMS doğrulama için
    
    uint256 maxBudget;
    uint256 acceptedAmount;
    
    uint64 createdAt;
    uint64 acceptedAt;
    uint64 pickupAt;
    uint64 deliveredAt;
    uint64 courierClaimTime;
    
    PackageType packageType;
    Urgency urgency;
    Status status;
    
    bool paymentReleased;
    bool rated;
    bool disputed;
    bool courierClaimedDelivery;
    
    uint8 rating;
    bytes32 deliveryProofHash;
}

struct Bid {
    uint256 amount;
    uint16 estimatedMinutes;
    uint64 timestamp;
}
```

## State Variables

```solidity
mapping(uint256 => DeliveryRequest) public requests;
mapping(uint256 => mapping(address => Bid)) public bids;
mapping(uint256 => address[]) public bidderList;
mapping(uint256 => mapping(address => uint256)) public lockedBidDeposits;

mapping(address => uint256) public courierStake;
mapping(address => CourierStats) public courierStats;

uint256 public nextRequestId;
uint256 public constant BID_DEPOSIT = 1e18;
uint256 public constant MIN_COURIER_STAKE = 10e18;
uint256 public constant PLATFORM_FEE_BPS = 300;    // 3%
uint256 public constant REWARD_POOL_BPS = 500;     // 5%

address public platformTreasury;
address public rewardPool;
IERC20 public token;
ILeaderboard public leaderboard;
IOracle public oracle;
```

## Public/External Fonksiyonlar

### Flow 01 — Talep Oluşturma
```solidity
function createDeliveryRequest(
    bytes32 pickupHash,
    bytes32 deliveryHash,
    PackageType packageType,
    Urgency urgency,
    uint256 maxBudget,
    bytes32 recipientCommitment
) external returns (uint256 requestId);

function cancelRequest(uint256 requestId) external;
```

### Flow 02 — Teklif Verme
```solidity
function submitBid(
    uint256 requestId,
    uint256 bidAmount,
    uint16 estimatedMinutes,
    int32 courierLat,
    int32 courierLng
) external;

function withdrawBid(uint256 requestId) external;

function depositStake(uint256 amount) external;
function withdrawStake(uint256 amount) external;
```

### Flow 03 — Kurye Seçimi
```solidity
function acceptBid(uint256 requestId, address selectedCourier) external;
function claimRefund(uint256 requestId) external; // pull pattern için
```

### Flow 04 — Pickup Onayı
```solidity
function confirmPickup(
    uint256 requestId,
    int32 courierLat,
    int32 courierLng,
    bytes calldata customerSignature
) external;
```

### Flow 05 — Teslimat Onayı
```solidity
function courierClaimsDelivery(
    uint256 requestId,
    int32 courierLat,
    int32 courierLng,
    bytes32 photoHash
) external;

function confirmDeliveryByRecipient(
    uint256 requestId,
    int32 recipientLat,
    int32 recipientLng
) external;

function confirmDeliveryByCourier(
    uint256 requestId,
    bytes calldata oracleSignedProof
) external;

function claimDeliveryByTimeout(uint256 requestId) external;

function rejectDelivery(uint256 requestId, string calldata reason) external;
```

### Flow 06 — Ödeme (internal _releasePayment)
```solidity
function _releasePayment(uint256 requestId) internal;
```

### Flow 07 — Puanlama
```solidity
function submitRating(
    uint256 requestId,
    uint8 stars,
    bytes32 reviewIpfsHash
) external;
```

### Dispute
```solidity
function raiseDispute(
    uint256 requestId,
    DisputeReason reason,
    bytes32 evidenceIpfsHash
) external;

function resolveDispute(
    uint256 requestId,
    DisputeOutcome outcome
) external onlyDisputeManager;
```

## View Fonksiyonlar

```solidity
function getRequest(uint256 requestId) external view returns (DeliveryRequest memory);
function getBids(uint256 requestId) external view returns (Bid[] memory);
function getAverageRating(address courier) external view returns (uint256);
function getCourierStats(address courier) external view returns (CourierStats memory);
function getActiveBidCount(address courier) external view returns (uint256);
```

## Events

```solidity
event DeliveryRequested(uint256 indexed requestId, address indexed customer, uint256 maxBudget);
event BidSubmitted(uint256 indexed requestId, address indexed courier, uint256 amount);
event CourierSelected(uint256 indexed requestId, address indexed courier, uint256 amount);
event PickupConfirmed(uint256 indexed requestId, address indexed courier, uint256 timestamp);
event CourierClaimedDelivery(uint256 indexed requestId, uint256 timestamp);
event DeliveryConfirmed(uint256 indexed requestId, address indexed confirmer, uint256 timestamp);
event PaymentReleased(uint256 indexed requestId, address indexed courier, uint256 amount);
event RatingSubmitted(uint256 indexed requestId, address indexed courier, uint8 stars);
event DisputeRaised(uint256 indexed requestId, address indexed disputer, DisputeReason reason);
```

## Güvenlik

### Modifier'lar

```solidity
modifier onlyCustomer(uint256 requestId) {
    require(msg.sender == requests[requestId].customer, "Not customer");
    _;
}

modifier onlyCourier(uint256 requestId) {
    require(msg.sender == requests[requestId].acceptedCourier, "Not courier");
    _;
}

modifier inStatus(uint256 requestId, Status expected) {
    require(requests[requestId].status == expected, "Wrong status");
    _;
}

modifier notDisputed(uint256 requestId) {
    require(!requests[requestId].disputed, "Disputed");
    _;
}
```

### Koruma Mekanizmaları

- `ReentrancyGuard` tüm ödeme fonksiyonlarında
- `SafeERC20` tüm token transferlerinde
- Integer overflow kontrolü (Solidity 0.8+ otomatik)
- Front-running koruması (acceptBid için)
- Pausable (emergency stop için)

## Upgrade Stratejisi

MVP'de non-upgradable. v2'de:
- OpenZeppelin UUPS proxy pattern
- Timelock ile governance kontrolü
- Storage layout dikkatli planlanır

## Gas Optimizasyon Notları

- `DeliveryRequest` struct'ını storage slot'larına optimize et (packed)
- `uint64` timestamp'ler yeterli (2106 yılına kadar)
- Bidder listesi uzun olduğunda pull pattern kullan
- Event'lerden fazla veri oku (storage'a yaz yerine)

## Test Senaryoları

```
✅ Happy path: create → bid → accept → pickup → deliver → pay → rate
✅ Multiple bids → correct winner selected
✅ Cancelled after bid → refunds correct
✅ Courier doesn't pickup in time → timeout
✅ Courier claims delivery → 24h timeout → auto-confirm
✅ Recipient disputes → status goes to Disputed
✅ Rating after completion → average updates correctly
✅ Gas measurement on Monad testnet for each flow
```

## Claude Code ile Geliştirme Komutu Önerisi

```
"Read monadcarry-docs/contracts/DeliveryEscrow.md and 
monadcarry-docs/flows/01-08*.md files. 
Generate DeliveryEscrow.sol contract following the spec, 
with complete Foundry tests for each flow."
```
