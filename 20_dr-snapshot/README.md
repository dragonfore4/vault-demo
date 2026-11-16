# Scenario 2 — separate DC and DR clusters, snapshots shipped to DR, DNS switch

| VM | Site | node_id | IP | .env `VAULT_CONFIG` |
|---|---|---|---|---|
| VM1 | DC | dc-1 | 13.251.124.180 | dc.hcl |
| VM2 | DR | dr-1 | 18.138.224.190 | dr.hcl |

Two independent single-node Raft clusters. No `retry_join` between them.
Security group: 8200 from clients; SSH from DC to DR (for scp).

## 0. Setup (each VM)

```bash
cp .env.example .env            # set VAULT_CONFIG and the other values
mkdir -p data snapshots && sudo chown -R 100:1000 data snapshots
docker compose up -d
```

## 1. Init DC and DR

```bash
# DC
docker exec -it vault vault operator init -key-shares=3 -key-threshold=2
docker exec -it vault vault operator unseal      # x2

# DR (gets its own keys; they are replaced by DC's keys after the restore)
docker exec -it vault vault operator init -key-shares=3 -key-threshold=2
docker exec -it vault vault operator unseal      # x2
```

## 2. Snapshot policy + token on DC

```bash
docker cp config/snapshot-policy.hcl vault:/tmp/snapshot-policy.hcl
docker exec -e VAULT_TOKEN=<dc-root> vault vault policy write snapshot /tmp/snapshot-policy.hcl
docker exec -e VAULT_TOKEN=<dc-root> vault vault token create -policy=snapshot -period=720h
#   -> put it in DC .env as SNAPSHOT_TOKEN
```

Set up SSH key auth from DC to DR, then test and schedule:

```bash
chmod +x scripts/*.sh
./scripts/snapshot-and-ship.sh
crontab -e   # */5 * * * * /home/ubuntu/vault/dr-snapshot/scripts/snapshot-and-ship.sh >> /var/log/vault-snapshot.log 2>&1
```

Write demo data on DC before the next snapshot:

```bash
docker exec -e VAULT_TOKEN=<dc-root> vault vault secrets enable -path=kv kv-v2
docker exec -e VAULT_TOKEN=<dc-root> vault vault kv put kv/demo msg="written on DC"
```

## 3. Simulate DC failure

Stop the DC VM. Clients get connection errors on `vault.example.com`.

## 4. Failover on DR

```bash
chmod +x scripts/*.sh
# RESTORE_TOKEN in .env = DR root token (from DR init)
./scripts/failover.sh
```

After the restore:
- DR holds DC's data, tokens and policies.
- **Unseal keys and root token are now DC's**, so unseal with the DC keys if the node is sealed.
- Anything written on DC after the last snapshot is lost (RPO = snapshot interval).

Verify with the DC root token:

```bash
docker exec -e VAULT_TOKEN=<dc-root> vault vault kv get kv/demo
```

DNS: the script updates Route 53 when `ROUTE53_ZONE_ID` is set. For a quick demo, edit `/etc/hosts` on your laptop so `vault.example.com` points to the DR IP.

## 5. Failback

Do not start the old DC with its stale data and repoint DNS. Take a snapshot from DR, wipe the DC `data/`, init it fresh, restore the DR snapshot with `-force`, then switch DNS back.

## Caveats

- Plain HTTP means clients keep working after a DNS switch. With TLS, the certificate must cover the shared DNS name on both sites.
- Lease and token state is in the snapshot, but in-flight dynamic secrets may need re-issuing.
- Use a short DNS TTL (30s in the script), and remember some clients cache DNS longer.
- This is cold standby. For continuous replication you need Vault Enterprise DR Replication.
