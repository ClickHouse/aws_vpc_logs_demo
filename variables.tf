// variables.tf
// ---------------------------------------------------------------------
// This file declares all variables used in the project.
// Values should be provided via terraform.tfvars or secret.tfvars
// ---------------------------------------------------------------------

// AWS Configuration
variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
}

// Deployment Flags
variable "deploy_vpc" {
  description = "Flag to deploy VPC resource"
  type        = bool
}

variable "deploy_s3" {
  description = "Flag to deploy S3 bucket resource"
  type        = bool
}

variable "deploy_flow_logs" {
  description = "Flag to deploy VPC Flow Logs resource"
  type        = bool
}

variable "deploy_simulator" {
  description = "Flag to deploy an EC2 instance that simulates traffic"
  type        = bool
}

variable "deploy_clickhouse" {
  description = "Flag to deploy ClickHouse service"
  type        = bool
}

variable "deploy_clickpipe" {
  description = "Flag to deploy ClickHouse ClickPipe for VPC Flow Logs"
  type        = bool
}

// VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for the new VPC"
  type        = string
}

variable "vpc_id" {
  description = "Existing VPC ID if deploy_vpc is false"
  type        = string
}

// S3 Configuration
variable "s3_bucket_name" {
  description = "Name for the S3 bucket (must be globally unique)"
  type        = string
}

variable "s3_bucket_private" {
  description = "Whether the S3 bucket should be private"
  type        = bool
}

variable "s3_bucket_arn" {
  description = "Existing S3 Bucket ARN if deploy_s3 is false"
  type        = string
}

// Flow Logs Configuration
variable "flow_logs_traffic_type" {
  description = "Traffic type to log (ALL, ACCEPT, REJECT)"
  type        = string
}

variable "max_aggregation_interval" {
  description = "Maximum aggregation interval for flow logs"
  type        = number
}

// EC2 Simulator Configuration
variable "existing_subnet_id" {
  description = "Existing Subnet ID if deploy_vpc is false and deploy_simulator is true"
  type        = string
}

// ClickHouse Cloud Credentials
variable "organization_id" {
  description = "ClickHouse Cloud organization ID"
  type        = string
  sensitive   = true
}

variable "token_key" {
  description = "ClickHouse Cloud API token key"
  type        = string
  sensitive   = true
}

variable "token_secret" {
  description = "ClickHouse Cloud API token secret"
  type        = string
  sensitive   = true
}

// ClickHouse Service Configuration
variable "clickhouse_service_name" {
  description = "Name for the ClickHouse service"
  type        = string
}

variable "clickhouse_region" {
  description = "AWS region for ClickHouse service"
  type        = string
}

variable "clickhouse_tier" {
  description = "Tier for the ClickHouse service"
  type        = string
}

variable "clickhouse_ip_access" {
  description = "IP access configuration for ClickHouse service"
  type = list(object({
    source      = string
    description = string
  }))
}

variable "clickhouse_num_replicas" {
  description = "Number of replicas for ClickHouse service (only used for non-development tiers)"
  type        = number
}

variable "clickhouse_min_memory" {
  description = "Minimum memory in GB for ClickHouse service replicas (only used for non-development tiers)"
  type        = number
}

variable "clickhouse_max_memory" {
  description = "Maximum memory in GB for ClickHouse service replicas (only used for non-development tiers)"
  type        = number
}

variable "clickhouse_idle_timeout" {
  description = "Idle timeout in minutes for ClickHouse service"
  type        = number
}

variable "service_password" {
  description = "Password for the ClickHouse service"
  type        = string
  sensitive   = true
}

// ClickPipe Configuration
variable "clickpipe_format" {
  description = "Format of the data in S3 for ClickPipe"
  type        = string
}

variable "clickpipe_s3_url" {
  description = "S3 URL for ClickPipe if not using the deployed S3 bucket"
  type        = string
}

variable "clickpipe_table_name" {
  description = "Table name for ClickPipe destination"
  type        = string
}

variable "clickpipe_columns" {
  description = "Column definitions for ClickPipe destination table"
  type = list(object({
    name = string
    type = string
  }))
}

variable "clickhouse_iam_role_arn" {
  description = "The IAM role ARN of the ClickHouse service (obtained after creating the ClickHouse service). Leave empty for initial deployment."
  type        = string
  default     = "" # Empty string means IAM role resources won't be created initially
}

variable "clickhouse_iam_role_name" {
  description = "The name of the IAM role for ClickHouse service"
  type        = string
  default     = ""
}

variable "clickpipe_is_continuous" {
  description = "Whether the ClickPipe is continuous"
  type        = bool
  default     = false
}

variable "clickhouse_s3_access_role_arn" {
  description = "The ARN of the IAM role for ClickHouse service to access S3"
  type        = string
  default     = ""
}
