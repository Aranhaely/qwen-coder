# Prod environment — HA everywhere: 3 NATs, multi-AZ RDS, deletion protection.
environment = "prod"
aws_region  = "eu-central-1"

node_instance_types = ["m6i.xlarge"]
nodes_min           = 3
nodes_max           = 20
nodes_desired       = 3
spot_nodes_max      = 40

enable_rds         = true
rds_pg_version     = "15.6"
rds_instance_class = "db.r6g.large" # memory-optimized, burstable is not prod-grade
rds_storage_gb     = 100
