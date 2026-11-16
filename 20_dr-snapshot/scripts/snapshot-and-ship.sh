#!/usr/bin/env bash
# Run on DC (cron). Takes a raft snapshot and copies it to the DR VM.
#   */5 * * * * /home/ubuntu/vault/dr-snapshot/scripts/snapshot-and-ship.sh >> /var/log/vault-snapshot.log 2>&1
set -euo pipefail

cd "$(dirname "$0")/.."
set -a; source .env; set +a

ts=$(date +%Y%m%d-%H%M%S)
name="vault-${ts}.snap"

# 1. Snapshot (written inside container to the mounted ./snapshots dir)
docker exec -e VAULT_TOKEN="$SNAPSHOT_TOKEN" vault \
  vault operator raft snapshot save "/vault/snapshots/${name}"

# 2. Ship to DR (write to .tmp then rename so DR never sees a half-copied file)
scp -q "snapshots/${name}" "${DR_SSH}:${DR_SNAPSHOT_DIR}/${name}.tmp"
ssh "$DR_SSH" "mv '${DR_SNAPSHOT_DIR}/${name}.tmp' '${DR_SNAPSHOT_DIR}/${name}' \
  && ln -sfn '${name}' '${DR_SNAPSHOT_DIR}/latest.snap'"

# 3. Rotate local copies
ls -1t snapshots/vault-*.snap | tail -n +"$((KEEP_LOCAL + 1))" | xargs -r rm -f

echo "$(date -Is) shipped ${name}"
