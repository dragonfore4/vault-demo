# Scenario 1 — 2 DC + 1 DR Raft cluster, DC down, recover with peers.json

| VM | Site | node_id | IP | .env `VAULT_CONFIG` |
|---|---|---|---|---|
| VM1 | DC | vault-1 | 13.251.124.180 | vault1.hcl |
| VM2 | DC | vault-2 | 13.212.227.50  | vault2.hcl |
| VM3 | DR | vault-3 | 18.138.224.190 | vault3.hcl |

Security group: allow 8200 + 8201 between all 3 VMs, 8200 from your IP.

## 0. Setup (each VM)

```bash
cp .env.example .env          # set VAULT_CONFIG for this VM
sudo chown -R 100:1000 data   # vault user inside container
docker compose up -d
```

## 1. Init + unseal (normal operation)

```bash
# VM1 only
docker exec -it vault vault operator init -key-shares=3 -key-threshold=2
#   -> save unseal keys + root token

# VM1, VM2, VM3 (2 keys each)
docker exec -it vault vault operator unseal

# verify (any node)
export VAULT_TOKEN=<root>
docker exec -e VAULT_TOKEN -it vault vault operator raft list-peers
#   expect 3 voters, leader on one of them
```

Write test data so you can prove it survives:

```bash
docker exec -e VAULT_TOKEN -it vault vault secrets enable -path=kv kv-v2
docker exec -e VAULT_TOKEN -it vault vault kv put kv/demo msg="written before DC failure"
```

## 2. Simulate DC failure

Stop **both** DC VMs (EC2 console → Stop, or `docker compose stop` on VM1 + VM2).

On VM3, observe the outage:

```bash
docker exec -it vault vault status        # HA Mode: standby, no active node
docker exec -e VAULT_TOKEN -it vault vault kv get kv/demo   # fails / hangs
```

Quorum is 2 of 3, so the DR node alone cannot elect a leader.

## 3. Recover DR with peers.json

```bash
# VM3
sudo ./scripts/recover-peers-json.sh      # checks DC is unreachable first
docker exec -it vault vault operator unseal   # x2
docker exec -e VAULT_TOKEN -it vault vault operator raft list-peers   # only vault-3, leader
docker exec -e VAULT_TOKEN -it vault vault kv get kv/demo            # data is back
```

Point clients/DNS to `18.138.224.190`. Prove DR is writable:

```bash
docker exec -e VAULT_TOKEN -it vault vault kv put kv/demo msg="written on DR"
```

## 4. Failback (DC returns)

> ⚠️ Do **not** just start VM1+VM2 with their old data. They still believe the
> cluster is {1,2,3}, form a quorum of 2 on their own, and you get **split brain**
> (two leaders, two versions of `kv/demo`).

On VM1, then VM2:

```bash
sudo ./scripts/failback-reset-node.sh     # moves old data aside, rejoins vault-3
docker exec -it vault vault operator unseal   # x2
```

On VM3: `vault operator raft list-peers` shows 3 voters again.
Optional: move leadership back to DC with `vault operator step-down` on VM3.

## What this demo shows

- 2+1 survives losing **one** node or the DR site, **not** the DC.
- peers.json is a manual break-glass step; RTO = time to notice + run script + unseal.
- RPO ≈ 0 only for writes that reached vault-3 before the DC died.
- Fencing (making sure DC is really down) is the critical step.
