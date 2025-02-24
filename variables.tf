// variables.tf
// ---------------------------------------------------------------------
// This file declares all variables used in the project.
// Customize the defaults as needed, or pass in overrides via command-line flags.
// ---------------------------------------------------------------------

// AWS region for deployment
variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-southeast-1"
}

// Flags to control resource deployment.
// Set to "false" if you want to use an existing resource instead.
variable "deploy_vpc" {
  description = "Flag to deploy VPC resource"
  type        = bool
  default     = true
}

variable "deploy_s3" {
  description = "Flag to deploy S3 bucket resource"
  type        = bool
  default     = true
}

variable "deploy_flow_logs" {
  description = "Flag to deploy VPC Flow Logs resource"
  type        = bool
  default     = true
}

// Flag to deploy an EC2 instance that generates traffic.
variable "deploy_simulator" {
  description = "Flag to deploy an EC2 instance that simulates traffic"
  type        = bool
  default     = true
}

// VPC configuration: CIDR block for new VPC.
variable "vpc_cidr" {
  description = "CIDR block for the new VPC"
  type        = string
  default     = "10.0.0.0/16"
}

// S3 Bucket configuration: Bucket name must be globally unique.
variable "s3_bucket_name" {
  description = "Name for the S3 bucket (must be globally unique)"
  type        = string
  default     = "ch-vpc-flow-logs-apac-sa-demo-001"
}

// S3 Bucket access configuration
variable "s3_bucket_private" {
  description = "Whether the S3 bucket should be private (default: false for public access)"
  type        = bool
  default     = false
}

// Flow log options
variable "flow_logs_traffic_type" {
  description = "Traffic type to log (ALL, ACCEPT, REJECT)"
  type        = string
  default     = "ALL"
}

# variable "flow_logs_log_format" {
#   description = "Log format for flow logs (parquet or plain-text)"
#   type        = string
#   default     = "parquet"
# }

// If not deploying a new VPC, provide an existing VPC ID.
variable "vpc_id" {
  description = "Existing VPC ID if deploy_vpc is false"
  type        = string
  default     = ""
}

// If not deploying a new S3 bucket, provide an existing S3 Bucket ARN.
variable "s3_bucket_arn" {
  description = "Existing S3 Bucket ARN if deploy_s3 is false"
  type        = string
  default     = ""
}

// For the simulator EC2 instance, if not deploying a new VPC, supply an existing subnet ID.
variable "existing_subnet_id" {
  description = "Existing Subnet ID if deploy_vpc is false and deploy_simulator is true"
  type        = string
  default     = ""
}

// Maximum aggregation interval for flow logs, value can be somewhere between 60 and 600 seconds
variable "max_aggregation_interval" {
  description = "Maximum aggregation interval for flow logs"
  type        = number
  default     = 60
}
