variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Short project identifier used in resource names"
  type        = string
  default     = "myapp"
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "owner" {
  description = "Team/owner tag value"
  type        = string
  default     = "platform-team"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "eks_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.29"
}

# --- Nodes ------------------------------------------------------------------
variable "node_instance_types" {
  description = "Instance types for the on-demand core node group"
  type        = list(string)
  default     = ["m6i.large"]
}

variable "spot_instance_types" {
  description = "Instance types for the spot workers node group"
  type        = list(string)
  default     = ["m6i.xlarge", "m5.xlarge", "c6i.xlarge"]
}

variable "nodes_min" {
  type    = number
  default = 2
}

variable "nodes_max" {
  type    = number
  default = 10
}

variable "nodes_desired" {
  type    = number
  default = 2
}

variable "spot_nodes_max" {
  type    = number
  default = 20
}

# --- RDS ---------------------------------------------------------------------
variable "enable_rds" {
  description = "Provision an RDS PostgreSQL instance"
  type        = bool
  default     = true
}

variable "rds_pg_version" {
  type    = string
  default = "15.6"
}

variable "rds_instance_class" {
  type    = string
  default = "db.t4g.medium"
}

variable "rds_storage_gb" {
  type    = number
  default = 20
}

variable "db_name" {
  type    = string
  default = "app"
}

variable "db_username" {
  type      = string
  default   = "app_user"
  sensitive = false # master user is separate; this is a low-privilege app user
}
