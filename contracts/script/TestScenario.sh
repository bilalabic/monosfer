#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${CONTRACT_ADDRESS:-}" ]]; then
  echo "Hata: CONTRACT_ADDRESS tanimli degil."
  echo "Ornek: export CONTRACT_ADDRESS=0x..."
  exit 1
fi

if [[ -z "${PRIVATE_KEY:-}" ]]; then
  echo "Hata: PRIVATE_KEY tanimli degil."
  echo "Ornek: export PRIVATE_KEY=0x..."
  exit 1
fi

RPC_URL="${RPC_URL:-https://testnet-rpc.monad.xyz}"

echo "Delivera test senaryosu basliyor..."
echo "Contract: ${CONTRACT_ADDRESS}"
echo "RPC: ${RPC_URL}"

PICKUP_HASH="$(cast keccak "Ulus Ankara")"
DELIVERY_HASH="$(cast keccak "Cankaya Ankara")"

echo
echo "[1/8] Kurye kaydi (0.01 MON stake)"
TX1=$(cast send "$CONTRACT_ADDRESS" "registerCourier()" \
  --value 0.01ether \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" | rg "transactionHash" -N)
echo "$TX1"

echo
echo "[2/8] Talep olusturma (0.05 MON budget, Express)"
TX2=$(cast send "$CONTRACT_ADDRESS" "createDeliveryRequest(bytes32,bytes32,uint8)" \
  "$PICKUP_HASH" "$DELIVERY_HASH" 1 \
  --value 0.05ether \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" | rg "transactionHash" -N)
echo "$TX2"

echo
echo "[3/8] Teklif verme (requestId=0, 0.04 MON, 25 dakika)"
TX3=$(cast send "$CONTRACT_ADDRESS" "submitBid(uint256,uint256,uint16)" \
  0 40000000000000000 25 \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" | rg "transactionHash" -N)
echo "$TX3"

echo
echo "[4/8] Musteri teklifi kabul etme (requestId=0)"
TX4=$(cast send "$CONTRACT_ADDRESS" "acceptBid(uint256,address)" \
  0 "$(cast wallet address --private-key "$PRIVATE_KEY")" \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" | rg "transactionHash" -N)
echo "$TX4"

echo
echo "[5/8] Pickup onayi"
TX5=$(cast send "$CONTRACT_ADDRESS" "confirmPickup(uint256)" \
  0 \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" | rg "transactionHash" -N)
echo "$TX5"

echo
echo "[6/8] Delivery onayi"
TX6=$(cast send "$CONTRACT_ADDRESS" "confirmDelivery(uint256)" \
  0 \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" | rg "transactionHash" -N)
echo "$TX6"

echo
echo "[7/8] Rating gonderimi (5 yildiz)"
TX7=$(cast send "$CONTRACT_ADDRESS" "submitRating(uint256,uint8)" \
  0 5 \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" | rg "transactionHash" -N)
echo "$TX7"

echo
echo "[8/8] Leaderboard okuma"
cast call "$CONTRACT_ADDRESS" "getLeaderboard(uint256)" 10 --rpc-url "$RPC_URL"

echo
echo "Senaryo tamamlandi."
