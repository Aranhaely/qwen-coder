# =============================================================================
# Terraform: production-grade VPC + EKS (autoscaling) + RDS + security
# Cloud: AWS. Regions/VPC sizing parameterized via variables.tf
# State: S3 + DynamoDB locking (see backend.tf). Secrets: never in tfvars —
#        pulled from SSM/Secrets Manager at runtime (db_master_password).
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
    }
  }
}

data "aws_availability_zones" "available" {}

data "aws_ssm_parameter" "db_master_password" {
  name = "/${var.project_name}/${var.environment}/rds/master-password"
}

# -----------------------------------------------------------------------------
# Network: VPC with public/private subnets across 3 AZs + NAT
# -----------------------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8"

  name = "${var.project_name}-${var.environment}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, i)]
  public_subnets  = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, 100 + i)]

  enable_nat_gateway     = true
  single_nat_gateway     = var.environment != "prod" # cost saving for non-prod
  one_nat_gateway_per_az = var.environment == "prod"

  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnets_per_az_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnets_per_az_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = {
    Environment = var.environment
    "kubernetes.io/cluster/${var.project_name}-${var.environment}" = "shared"
  }
}

# -----------------------------------------------------------------------------
# EKS cluster + managed node groups (autoscaling via Karpenter-friendly ASGs)
# -----------------------------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.8"

  cluster_name    = "${var.project_name}-${var.environment}"
  cluster_version = var.eks_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true

  # OIDC provider for IRSA (IAM Roles for Service Accounts)
  cluster_enabled_log_types = ["api", "audit", "controllerManager", "scheduler"]

  eks_managed_node_groups = {
    core = {
      name           = "core"
      instance_types = var.node_instance_types
      min_size       = var.nodes_min
      max_size       = var.nodes_max
      desired_size   = var.nodes_desired
      capacity_type  = "ON_DEMAND"

      pre_bootstrap_user_data = <<-EOT
        echo "EKS node bootstrapped by terraform"
      EOT
    }

    spot = {
      name                 = "spot-workers"
      instance_types       = var.spot_instance_types
      capacity_type        = "SPOT"
      min_size             = 0
      max_size             = var.spot_nodes_max
      desired_size         = 0
      force_dispatch_images = false
    }
  }

  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
  }

  tags = {
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# RDS PostgreSQL (private subnet, no public access, encrypted, PITR backups)
# -----------------------------------------------------------------------------
module "rds" {
  count = var.enable_rds ? 1 : 0

  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.6"

  identifier = "${var.project_name}-${var.environment}-db"

  engine               = "postgres"
  engine_version       = var.rds_pg_version
  family               = "postgres15"
  major_engine_version = "15"
  instance_class       = var.rds_instance_class

  allocated_storage     = var.rds_storage_gb
  max_allocated_storage = var.rds_storage_gb * 2
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = data.aws_ssm_parameter.db_master_password.value
  port     = 5432

  multi_az               = var.environment == "prod"
  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [module.rds_sg[0].security_group_id]

  publicly_accessible   = false
  create_db_subnet_group = false

  backup_retention_period = 14
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"
  performance_insights_enabled = true

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  deletion_protection       = var.environment == "prod"
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project_name}-${var.environment}-db-final"

  tags = {
    Environment = var.environment
  }
}

# Dedicated SG for RDS: only EKS nodes may connect on 5432
module "rds_sg" {
  count = var.enable_rds ? 1 : 0

  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.1"

  name        = "${var.project_name}-${var.environment}-rds-sg"
  description = "Access to RDS from EKS nodes only"
  vpc_id      = module.vpc.vpc_id

  ingress_with_source_security_group_id = [
    {
      rule                     = "postgresql-tcp"
      source_security_group_id = module.eks.node_security_group_id
    }
  ]

  egress_rules = ["all-all"]
}

# -----------------------------------------------------------------------------
# S3 buckets: app artifacts + terraform state lives in a separate bootstrap
# account/stack (see backend.tf); here we create the application bucket.
# -----------------------------------------------------------------------------
module "s3_app" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.1"

  bucket_prefix = "${var.project_name}-${var.environment}-app-"
  force_destroy = false

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  versioning = {
    enabled = true
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "aws:kms"
      }
    }
  }

  lifecycle_rule = [
    {
      id      = "expire-old-noncurrent"
      enabled = true
      noncurrent_version_expiration = {
        days = 90
      }
    }
  ]

  tags = {
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# Outputs consumed by CI/CD and kubectl
# -----------------------------------------------------------------------------
output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_ca_certificate" {
  value     = module.eks.cluster_certificate_authority_data
  sensitive = true
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "db_endpoint" {
  value = var.enable_rds ? module.rds[0].db_instance_endpoint : null
}

output "app_bucket" {
  value = module.s3_app.s3_bucket_id
}
