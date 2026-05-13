// variables.tf
// ---------------------------------------------------------------------
// Variable declarations for both pipelines:
//   - Batch pipeline (VPC Flow Logs -> S3 -> ClickPipe)
//   - Streaming pipeline (CloudWatch Logs -> Lambda -> Kinesis -> ClickPipe)
// Values should be provided via terraform.tfvars or secret.tfvars.
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
  description = "Flag to deploy ClickHouse S3 ClickPipe for VPC Flow Logs (batch pipeline)"
  type        = bool
}

// Streaming pipeline flags
variable "deploy_cloudwatch_logs" {
  description = "Flag to deploy the CloudWatch Logs group used by the streaming pipeline"
  type        = bool
  default     = false
}

variable "deploy_kinesis_stream" {
  description = "Flag to deploy the Kinesis Data Stream used by the streaming pipeline"
  type        = bool
  default     = false
}

variable "deploy_lambda_transformer" {
  description = "Flag to deploy the Lambda function that decompresses CloudWatch Logs subscription events and forwards them to Kinesis"
  type        = bool
  default     = false
}

variable "deploy_cloudwatch_clickpipe" {
  description = "Flag to deploy the Kinesis ClickPipe that ingests transformed CloudWatch Logs events into ClickHouse (streaming pipeline)"
  type        = bool
  default     = false
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

// ---------------------------------------------------------------------
// Streaming pipeline configuration (CloudWatch Logs -> Kinesis -> ClickPipe)
// ---------------------------------------------------------------------

// CloudWatch Logs
variable "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch Logs group that receives EC2 simulator logs"
  type        = string
  default     = "/apac-sa-demo/app"
}

variable "cloudwatch_log_retention_days" {
  description = "Retention (in days) for the CloudWatch Logs group"
  type        = number
  default     = 7
}

variable "cloudwatch_subscription_filter_pattern" {
  description = "Filter pattern for the CloudWatch Logs -> Lambda subscription. Empty string forwards all events."
  type        = string
  default     = ""
}

// Kinesis Data Stream
variable "kinesis_stream_name" {
  description = "Name of the Kinesis Data Stream that the Lambda forwards to and ClickPipe reads from"
  type        = string
  default     = "apac-sa-demo-log-stream"
}

variable "kinesis_stream_mode" {
  description = "Kinesis capacity mode: ON_DEMAND (recommended for demos) or PROVISIONED"
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "PROVISIONED"], var.kinesis_stream_mode)
    error_message = "kinesis_stream_mode must be ON_DEMAND or PROVISIONED."
  }
}

variable "kinesis_shard_count" {
  description = "Shard count for the Kinesis Data Stream (only used when stream_mode is PROVISIONED)"
  type        = number
  default     = 1
}

variable "kinesis_retention_hours" {
  description = "Retention (in hours) for records on the Kinesis Data Stream. AWS minimum is 24."
  type        = number
  default     = 24
}

// Lambda transformer
variable "lambda_function_name" {
  description = "Name of the Lambda function that transforms CloudWatch Logs subscription events"
  type        = string
  default     = "apac-sa-demo-cw-to-kinesis"
}

variable "lambda_iam_role_name" {
  description = "Name of the IAM role assumed by the Lambda transformer"
  type        = string
  default     = "apac-sa-demo-cw-to-kinesis-role"
}

// ClickHouse Kinesis IAM role
variable "clickhouse_kinesis_iam_role_name" {
  description = "Name of the IAM role that the Kinesis ClickPipe assumes. Use the ClickHouseAccess- naming convention to match the existing S3 role."
  type        = string
  default     = "ClickHouseAccess-ClickPipe-Kinesis-Demo"
}

// Kinesis ClickPipe configuration
variable "cloudwatch_clickpipe_format" {
  description = "Wire format on the Kinesis stream. JSONEachRow matches what the Lambda transformer emits."
  type        = string
  default     = "JSONEachRow"
}

variable "cloudwatch_clickpipe_iterator_type" {
  description = "Kinesis iterator type: LATEST (recommended for streaming demos), TRIM_HORIZON, or AT_TIMESTAMP"
  type        = string
  default     = "LATEST"
}

variable "cloudwatch_clickpipe_use_enhanced_fan_out" {
  description = "Use a Kinesis enhanced fan-out consumer for dedicated throughput per shard"
  type        = bool
  default     = false
}

variable "cloudwatch_clickpipe_table_name" {
  description = "Destination table name for the streaming CloudWatch Logs pipeline"
  type        = string
  default     = "cloudwatch_logs"
}

variable "cloudwatch_clickpipe_columns" {
  description = "Column definitions for the cloudwatch_logs destination table. Must match the JSON keys emitted by lambda/cw_to_kinesis.py."
  type = list(object({
    name = string
    type = string
  }))
  default = [
    { name = "log_group", type = "String" },
    { name = "log_stream", type = "String" },
    { name = "owner", type = "String" },
    { name = "timestamp", type = "UInt64" },
    { name = "id", type = "String" },
    { name = "message", type = "String" },
  ]
}
