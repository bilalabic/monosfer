#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${ESCROW_ADDRESS:-}" || -z "${TOKEN_ADDRESS:-}" || -z "${LEADERBOARD_ADDRESS:-}" ]]; then
  echo "Hata: ESCROW_ADDRESS, TOKEN_ADDRESS ve LEADERBOARD_ADDRESS tanimli olmali."
  exit 1
fi

if [[ -z "${CUSTOMER_PRIVATE_KEY:-}" || -z "${COURIER_PRIVATE_KEY:-}" ]]; then
  echo "Hata: CUSTOMER_PRIVATE_KEY ve COURIER_PRIVATE_KEY tanimli olmali."
  exit 1
fi

RPC_URL="${RPC_URL:-https://testnet-rpc.monad.xyz}"
EXPECTED_CHAIN_ID="${EXPECTED_CHAIN_ID:-10143}"

CUSTOMER_ADDRESS="$(cast wallet address --private-key "$CUSTOMER_PRIVATE_KEY")"
COURIER_ADDRESS="$(cast wallet address --private-key "$COURIER_PRIVATE_KEY")"

PICKUP_HASH="$(cast keccak "Kayseri Forum")"
DELIVERY_HASH="$(cast keccak "Kayseri Talas")"

echo "Moduler sistem test senaryosu basliyor..."
echo "Customer: $CUSTOMER_ADDRESS"
echo "Courier: $COURIER_ADDRESS"
echo "Escrow: $ESCROW_ADDRESS"
echo "Token: $TOKEN_ADDRESS"
echo "Leaderboard: $LEADERBOARD_ADDRESS"

CHAIN_ID="$(cast chain-id --rpc-url "$RPC_URL")"
if [[ "$CHAIN_ID" != "$EXPECTED_CHAIN_ID" ]]; then
  echo "Hata: Yanlis ag. Beklenen chain id: $EXPECTED_CHAIN_ID, gelen: $CHAIN_ID"
  exit 1
fi

echo
echo "[1/10] Kurye stake icin approve (10 MON)"
cast send "$TOKEN_ADDRESS" "approve(address,uint256)" \
  "$ESCROW_ADDRESS" 10000000000000000000 \
  --rpc-url "$RPC_URL" \
  --private-key "$COURIER_PRIVATE_KEY"

echo
echo "[2/10] Kurye stake yatirma (10 MON)"
cast send "$ESCROW_ADDRESS" "depositStake(uint256)" \
  10000000000000000000 \
  --rpc-url "$RPC_URL" \
  --private-key "$COURIER_PRIVATE_KEY"

echo
echo "[3/10] Musteri budget icin approve (50 MON)"
cast send "$TOKEN_ADDRESS" "approve(address,uint256)" \
  "$ESCROW_ADDRESS" 50000000000000000000 \
  --rpc-url "$RPC_URL" \
  --private-key "$CUSTOMER_PRIVATE_KEY"

echo
echo "[4/10] Talep olusturma (Express, 50 MON)"
cast send "$ESCROW_ADDRESS" "createDeliveryRequest(bytes32,bytes32,uint8,uint256)" \
  "$PICKUP_HASH" "$DELIVERY_HASH" 1 50000000000000000000 \
  --rpc-url "$RPC_URL" \
  --private-key "$CUSTOMER_PRIVATE_KEY"

REQUEST_ID=$(cast call "$ESCROW_ADDRESS" "nextRequestId()" --rpc-url "$RPC_URL")
REQUEST_ID=$((REQUEST_ID - 1))
echo "Aktif requestId: $REQUEST_ID"

echo
echo "[5/10] Teklif verme (requestId=0, 40 MON, 25 dakika)"
cast send "$ESCROW_ADDRESS" "submitBid(uint256,uint256,uint16)" \
  "$REQUEST_ID" 40000000000000000000 25 \
  --rpc-url "$RPC_URL" \
  --private-key "$COURIER_PRIVATE_KEY"

echo
echo "[6/10] Musteri teklif kabul"
cast send "$ESCROW_ADDRESS" "acceptBid(uint256,address)" \
  "$REQUEST_ID" "$COURIER_ADDRESS" \
  --rpc-url "$RPC_URL" \
  --private-key "$CUSTOMER_PRIVATE_KEY"

echo
echo "[7/10] Kurye pickup onayi"
cast send "$ESCROW_ADDRESS" "confirmPickup(uint256)" \
  "$REQUEST_ID" \
  --rpc-url "$RPC_URL" \
  --private-key "$COURIER_PRIVATE_KEY"

echo
echo "[8/10] Musteri delivery onayi"
cast send "$ESCROW_ADDRESS" "confirmDelivery(uint256)" \
  "$REQUEST_ID" \
  --rpc-url "$RPC_URL" \
  --private-key "$CUSTOMER_PRIVATE_KEY"

echo
echo "[9/10] Musteri rating gonderimi (5 yildiz)"
cast send "$ESCROW_ADDRESS" "submitRating(uint256,uint8)" \
  "$REQUEST_ID" 5 \
  --rpc-url "$RPC_URL" \
  --private-key "$CUSTOMER_PRIVATE_KEY"

echo
echo "[10/10] Leaderboard ve request verilerini oku"
cast call "$LEADERBOARD_ADDRESS" "courierStats(address)" "$COURIER_ADDRESS" --rpc-url "$RPC_URL"
cast call "$ESCROW_ADDRESS" "requests(uint256)" "$REQUEST_ID" --rpc-url "$RPC_URL"

echo
echo "Moduler test senaryosu tamamlandi."
