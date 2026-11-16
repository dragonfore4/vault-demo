#!/usr/bin/env bash
# Run on the DR node (vault-3) ONLY after the DC is confirmed down.
# Forces vault-3 to become a single-node Raft cluster via peers.json.
#
# Usage: sudo ./scripts/recover-peers-json.sh [--force]
#   --force  skip the "are DC nodes really unreachable?" check (dangerous)
set -euo pipefail

cd "$(dirname "$0")/.."

DR_NODE_ID="vault-3"
DR_CLUSTER_ADDR="18.138.224.190:8201"           # host:port of cluster_addr, no scheme
DC_API_ADDRS=("http://13.251.124.180:8200" "http://13.212.227.50:8200")
RAFT_DIR="./data/raft"

# --- 1. Fencing check: refuse if any DC node still answers (split-brain risk)
if [[ "${1:-}" != "--force" ]]; then
  for addr in "${DC_API_ADDRS[@]}"; do
    if curl -s -o /dev/null --max-time 3 "$addr/v1/sys/health"; then
      echo "ABORT: $addr is still reachable. DC may be partitioned, not down."
      echo "Stop the DC nodes (or the EC2 instances) first, or rerun with --force."
      exit 1
    fi
  done
  echo "OK: no DC node reachable."
fi

# --- 2. Stop Vault on this node
docker compose stop vault

# --- 3. Write peers.json with only this node as voter
if [[ ! -d "$RAFT_DIR" ]]; then
  echo "ABORT: $RAFT_DIR not found - is this node's data dir correct?"
  exit 1
fi

cat > "$RAFT_DIR/peers.json" <<EOF
[
  {
    "id": "${DR_NODE_ID}",
    "address": "${DR_CLUSTER_ADDR}",
    "non_voter": false
  }
]
EOF
chown 100:1000 "$RAFT_DIR/peers.json"   # vault user inside the container
echo "Wrote $RAFT_DIR/peers.json"

# --- 4. Start Vault; it reads peers.json on boot (then deletes it)
docker compose start vault
sleep 3

echo
echo "Now unseal this node:   docker exec -it vault vault operator unseal"
echo "Then verify:            docker exec -it vault vault operator raft list-peers"
