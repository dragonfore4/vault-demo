#!/usr/bin/env bash
# Run on a DC node (vault-1 / vault-2) when the DC comes back AFTER peers.json recovery.
#
# Why: the DC nodes still hold the OLD Raft config (vault-1,2,3). If both start
# with old data, they form a quorum of 2 and elect their own leader -> split brain.
# So we move the old data aside and let the node rejoin vault-3 via retry_join.
#
# Usage: sudo ./scripts/failback-reset-node.sh
set -euo pipefail

cd "$(dirname "$0")/.."

docker compose stop vault 2>/dev/null || true

backup="./data.bak.$(date +%Y%m%d-%H%M%S)"
mv ./data "$backup"
mkdir -p ./data
chown 100:1000 ./data
echo "Old data moved to $backup"

docker compose up -d
sleep 3

echo
echo "Unseal this node (same keys as before) so it can join vault-3:"
echo "   docker exec -it vault vault operator unseal"
echo "Check from vault-3:  vault operator raft list-peers"
