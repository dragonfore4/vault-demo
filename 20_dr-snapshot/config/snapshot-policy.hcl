# Least-privilege policy for taking (DC) and force-restoring (DR) raft snapshots
path "sys/storage/raft/snapshot" {
  capabilities = ["read", "update"]
}

path "sys/storage/raft/snapshot-force" {
  capabilities = ["update"]
}
