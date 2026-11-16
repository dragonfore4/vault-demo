#!/usr/bin/env bash
# Run on DR when DC has failed.
#   1. restore the latest shipped snapshot into the DR cluster
#   2. (optional) repoint DNS to DR via Route 53
#
# Usage: ./scripts/failover.sh [snapshot-file]   (default: snapshots/latest.snap)
set -euo pipefail

cd "$(dirname "$0")/.."
set -a; source .env; set +a

snap="${1:-snapshots/latest.snap}"
[[ -e "$snap" ]] || { echo "ABORT: $snap not found"; exit 1; }
real=$(readlink -f "$snap")
echo "Restoring $(basename "$real")  (age: $(( ($(date +%s) - $(stat -c %Y "$real")) / 60 )) min)"

# 1. Restore. -force is required because the snapshot comes from a DIFFERENT cluster.
#    After this, DR has DC's data, DC's tokens and DC's unseal keys.
docker exec -e VAULT_TOKEN="$RESTORE_TOKEN" vault \
  vault operator raft snapshot restore -force "/vault/snapshots/$(basename "$real")"

sleep 3
docker exec vault vault status || true
echo
echo "If 'Sealed: true' -> unseal with the DC's unseal keys:"
echo "   docker exec -it vault vault operator unseal"

# 2. DNS switch (skipped if ROUTE53_ZONE_ID is empty)
if [[ -n "${ROUTE53_ZONE_ID:-}" ]]; then
  aws route53 change-resource-record-sets --hosted-zone-id "$ROUTE53_ZONE_ID" \
    --change-batch "{
      \"Comment\": \"Vault failover to DR\",
      \"Changes\": [{
        \"Action\": \"UPSERT\",
        \"ResourceRecordSet\": {
          \"Name\": \"${DNS_NAME}\", \"Type\": \"A\", \"TTL\": 30,
          \"ResourceRecords\": [{\"Value\": \"${DR_IP}\"}]
        }}]}"
  echo "DNS ${DNS_NAME} -> ${DR_IP}"
else
  echo "ROUTE53_ZONE_ID not set - switch DNS manually (or edit /etc/hosts for the demo)."
fi
