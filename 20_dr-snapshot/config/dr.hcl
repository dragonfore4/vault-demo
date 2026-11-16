ui            = true
disable_mlock = true

# Separate single-node cluster - NO retry_join to DC.
storage "raft" {
  path    = "/vault/data"
  node_id = "dr-1"
}

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable     = 1
}

api_addr     = "http://18.138.224.190:8200"
cluster_addr = "http://18.138.224.190:8201"
