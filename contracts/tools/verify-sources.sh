#!/bin/bash
# Submit every deployed V1 contract to Sourcify and report what actually matched.
#
# Two things this deliberately does not do. It does not trust the submission: a
# job id is a receipt for asking, not for succeeding, so every address is read
# back from the API afterwards. And it does not stop at the first failure, so one
# contract with awkward constructor arguments does not hide the state of the
# other twelve.
#
# Usage (from contracts/):   bash tools/verify-sources.sh [--check-only]
# Addresses come from deployments/<chainId>.json, so the manifest stays the one
# source of truth (sec. 6).
set -u

CHAIN_ID=${CHAIN_ID:-10143}
API=${SOURCIFY_API:-https://sourcify-api-monad.blockvision.org}
MANIFEST="deployments/${CHAIN_ID}.json"
CHECK_ONLY=${1:-}

[ -f "$MANIFEST" ] || { echo "  $MANIFEST yok"; exit 1; }

# Contract name -> source path. Only V1: the legacy set is frozen under decision
# D1 and retired at P5.3, so verifying it would be recording history as current.
declare -A SRC=(
  [ProtocolAccessManager]="src/v1/access/ProtocolAccessManager.sol"
  [ProtocolConfig]="src/v1/config/ProtocolConfig.sol"
  [SettlementVault]="src/v1/vault/SettlementVault.sol"
  [CourierRegistry]="src/v1/registry/CourierRegistry.sol"
  [DeliveryHub]="src/v1/hub/DeliveryHub.sol"
  [ReputationRegistry]="src/v1/reputation/ReputationRegistry.sol"
  [BadgeSBT]="src/v1/badge/BadgeSBT.sol"
  [Referral]="src/v1/rewards/Referral.sol"
  [RewardDistributorV1]="src/v1/rewards/RewardDistributor.sol"
  [PythEntropyAdapter]="src/v1/randomness/PythEntropyAdapter.sol"
  [JurorPool]="src/v1/dispute/JurorPool.sol"
  [FallbackCommittee]="src/v1/dispute/FallbackCommittee.sol"
  [DisputeCourt]="src/v1/dispute/DisputeCourt.sol"
)

address_of() {
  python3 -c "
import json,sys
d=json.load(open('$MANIFEST'))
c=d['contracts'].get('$1')
print(c['address'] if c else '')"
}

# A contract's real name differs from its manifest key only for the V1 reward
# distributor, which shares a name with the frozen legacy one.
contract_name() { [ "$1" = "RewardDistributorV1" ] && echo "RewardDistributor" || echo "$1"; }

matched() {
  curl -s --max-time 30 "$API/v2/contract/$CHAIN_ID/$1" 2>/dev/null | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    print(d.get('match') or 'none')
except Exception:
    print('none')"
}

submitted=0; ok=0; failed=0
for key in "${!SRC[@]}"; do
  addr=$(address_of "$key")
  if [ -z "$addr" ]; then printf "  %-22s manifestte yok\n" "$key"; continue; fi

  state=$(matched "$addr")
  if [ "$state" != "none" ]; then
    printf "  %-22s %s  zaten dogrulanmis (%s)\n" "$key" "${addr:0:10}" "$state"
    ok=$((ok+1)); continue
  fi
  if [ "$CHECK_ONLY" = "--check-only" ]; then
    printf "  %-22s %s  DOGRULANMAMIS\n" "$key" "${addr:0:10}"
    failed=$((failed+1)); continue
  fi

  forge verify-contract "$addr" "${SRC[$key]}:$(contract_name "$key")" \
    --chain-id "$CHAIN_ID" --verifier sourcify --verifier-url "$API" >/dev/null 2>&1
  submitted=$((submitted+1))

  # Poll rather than sleep once. A fixed wait reads the answer before it
  # exists and calls a success a failure -- which is what the first version
  # of this script did for eight of thirteen contracts.
  state=none
  for _ in $(seq 1 20); do
    sleep 3
    state=$(matched "$addr")
    [ "$state" != "none" ] && break
  done
  if [ "$state" != "none" ]; then
    printf "  %-22s %s  dogrulandi (%s)\n" "$key" "${addr:0:10}" "$state"
    ok=$((ok+1))
  else
    printf "  %-22s %s  BASARISIZ\n" "$key" "${addr:0:10}"
    failed=$((failed+1))
  fi
done

echo "  --- gonderilen: $submitted | dogrulanmis: $ok | basarisiz: $failed"
[ "$failed" -eq 0 ]
