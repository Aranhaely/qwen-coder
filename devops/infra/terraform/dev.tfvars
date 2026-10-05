# Dev environment — small, cheap, single NAT, no deletion protection.
environment = "dev"
aws_region  = "eu-central-1"

nodes_min      = 1
nodes_max      = 3
nodes_desired  = 1
spot_nodes_max = 5

enable_rds         = true
rds_instance_class = "db.t4g.micro"
rds_storage_gb     = 20
