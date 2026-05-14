// main.tf
// ---------------------------------------------------------------------
// Provider configuration and shared resources for the demo:
//   - VPC, S3 bucket, VPC Flow Logs (batch pipeline: S3 -> ClickPipe -> ClickHouse)
//   - ClickHouse Cloud service (shared by both pipelines)
//   - S3 ClickPipe (VPC Flow Logs batch ingestion)
//
// The streaming pipeline (CloudWatch Logs -> Lambda -> Kinesis -> ClickPipe)
// is defined in cloudwatch_logs.tf and reuses the ClickHouse service below.
// ---------------------------------------------------------------------

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    clickhouse = {
      source  = "ClickHouse/clickhouse"
      version = "~> 3.14"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

// Used by cloudwatch_logs.tf to build ARNs and the CloudWatch Logs service principal.
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

provider "aws" {
  region  = var.aws_region
  profile = "sa"
}

provider "clickhouse" {
  organization_id = var.organization_id
  token_key       = var.token_key
  token_secret    = var.token_secret
}

###############################
// VPC Resource
// ---------------------------------------------------------------------
// Create a new VPC if the flag "deploy_vpc" is true.
// If false, the user must supply an existing VPC ID via var.vpc_id.
###############################
resource "aws_vpc" "main" {
  count                = var.deploy_vpc ? 1 : 0
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "apac-sa-demo"
  }
}

###############################
// S3 Bucket Resource
// ---------------------------------------------------------------------
// Creates an S3 bucket for storing VPC Flow Logs when deploy_s3 is true.
// If false, an existing S3 bucket ARN must be provided via var.s3_bucket_arn.
###############################
resource "aws_s3_bucket" "flow_logs" {
  count         = var.deploy_s3 ? 1 : 0
  bucket        = var.s3_bucket_name
  force_destroy = true # This deletes all objects in the bucket when the bucket is destroyed, use for dev and testing only

  tags = {
    Name = "apac-sa-demo"
  }
}

# Enable versioning for the S3 bucket
resource "aws_s3_bucket_versioning" "flow_logs" {
  count  = var.deploy_s3 ? 1 : 0
  bucket = aws_s3_bucket.flow_logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

# Configure bucket access based on the s3_bucket_private flag
resource "aws_s3_bucket_public_access_block" "bucket_access" {
  count  = var.deploy_s3 ? 1 : 0
  bucket = aws_s3_bucket.flow_logs[0].id

  block_public_acls       = var.s3_bucket_private
  block_public_policy     = var.s3_bucket_private
  ignore_public_acls      = var.s3_bucket_private
  restrict_public_buckets = var.s3_bucket_private
}

# Add bucket policy for VPC Flow Logs and optional public access
resource "aws_s3_bucket_policy" "bucket_policy" {
  count  = var.deploy_s3 ? 1 : 0 # Always create policy for Flow Logs
  bucket = aws_s3_bucket.flow_logs[0].id

  # Ensure the public access block settings are applied first
  depends_on = [aws_s3_bucket_public_access_block.bucket_access]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid    = "AWSLogDeliveryWrite"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = ["s3:PutObject"]
        Resource = ["${aws_s3_bucket.flow_logs[0].arn}/*"]
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid    = "AWSLogDeliveryAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = ["s3:GetBucketAcl"]
        Resource = [aws_s3_bucket.flow_logs[0].arn]
      }
      ],
      # Add public read policy only if bucket is public
      var.s3_bucket_private ? [] : [
        {
          Sid       = "PublicReadGetObject"
          Effect    = "Allow"
          Principal = "*"
          Action    = "s3:GetObject"
          Resource  = "${aws_s3_bucket.flow_logs[0].arn}/*"
        }
    ])
  })
}

###############################
// Sample VPC Flow Log File
// ---------------------------------------------------------------------
// Creates and uploads a sample VPC flow log file to the S3 bucket
// to ensure the ClickPipe has data to process.
###############################
# resource "null_resource" "sample_flow_log" {
#   count = var.deploy_s3 ? 1 : 0

#   triggers = {
#     bucket_id = aws_s3_bucket.flow_logs[0].id
#   }

#   provisioner "local-exec" {
#     command = <<-EOT
#       # Create a temporary directory
#       TEMP_DIR=$(mktemp -d)

#       # Create a sample VPC flow log file
#       cat > $TEMP_DIR/sample-flow-log.log << 'EOF'
# version account-id interface-id srcaddr dstaddr srcport dstport protocol packets bytes start end action log-status
# EOF

#       # Compress the file with gzip
#       gzip $TEMP_DIR/sample-flow-log.log

#       # Upload the compressed file to S3
#       aws s3 cp $TEMP_DIR/sample-flow-log.log.gz s3://${aws_s3_bucket.flow_logs[0].bucket}/AWSLogs/sample-flow-log.log.gz

#       # Clean up
#       rm -rf $TEMP_DIR
#     EOT
#   }

#   depends_on = [aws_s3_bucket_policy.bucket_policy]
# }

###############################
// VPC Flow Logs Resource
// ---------------------------------------------------------------------
// Activates VPC Flow Logs for the given VPC and directs logs to the S3 bucket.
// Uses the deployed resources if available; otherwise, falls back to provided IDs.
###############################
resource "aws_flow_log" "vpc_flow_logs" {
  count = var.deploy_flow_logs ? 1 : 0

  // Use new VPC if deployed, otherwise use existing VPC ID from variable
  vpc_id = var.deploy_vpc ? aws_vpc.main[0].id : var.vpc_id

  // Use new S3 bucket ARN if deployed, otherwise use provided ARN
  log_destination          = var.deploy_s3 ? aws_s3_bucket.flow_logs[0].arn : var.s3_bucket_arn
  log_destination_type     = "s3"
  traffic_type             = var.flow_logs_traffic_type
  max_aggregation_interval = var.max_aggregation_interval
  destination_options {
    file_format        = "parquet"
    per_hour_partition = true
  }

  tags = {
    Name = "apac-sa-demo-flow-logs"
  }
}

###############################
// ClickHouse Resources
// ---------------------------------------------------------------------
// Creates a ClickHouse service for ingesting VPC Flow Logs
###############################
resource "clickhouse_service" "service" {
  count                 = var.deploy_clickhouse ? 1 : 0
  name                  = var.clickhouse_service_name
  cloud_provider        = "aws"
  region                = var.clickhouse_region
  idle_scaling          = false # Set to false to keep the service running
  ip_access             = var.clickhouse_ip_access
  num_replicas          = var.clickhouse_num_replicas
  min_replica_memory_gb = var.clickhouse_min_memory
  max_replica_memory_gb = var.clickhouse_max_memory
  idle_timeout_minutes  = null # Must be null when idle_scaling is disabled
  password              = var.service_password
}

###############################
// IAM Resources for ClickHouse
// ---------------------------------------------------------------------
// Creates IAM policy and role for ClickHouse to access S3 bucket
###############################
# Define locals for IAM role
locals {
  # Get the IAM role from the ClickHouse service when it's deployed
  clickhouse_iam_role = var.deploy_clickhouse ? clickhouse_service.service[0].iam_role : null
}

# IAM policy for ClickHouse to access S3
resource "aws_iam_policy" "clickhouse_s3_access" {
  name        = "ClickHouseS3AccessPolicy"
  description = "Policy allowing ClickHouse to access VPC flow logs in S3"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = ["s3:GetBucketLocation", "s3:ListBucket"],
        Resource = ["arn:aws:s3:::${var.deploy_s3 ? aws_s3_bucket.flow_logs[0].bucket : var.s3_bucket_name}"],
        Effect   = "Allow"
      },
      {
        Action   = ["s3:Get*", "s3:List*"],
        Resource = ["arn:aws:s3:::${var.deploy_s3 ? aws_s3_bucket.flow_logs[0].bucket : var.s3_bucket_name}/*"],
        Effect   = "Allow"
      }
    ]
  })
  depends_on = [aws_s3_bucket.flow_logs]
}

# IAM role that ClickHouse Cloud assumes to read VPC Flow Logs from S3.
# The trust policy is written inline using clickhouse_service.service[0].iam_role;
# Terraform's dependency graph guarantees the ClickHouse service is provisioned
# before this role is created, so the ARN is always known at create time.
resource "aws_iam_role" "clickhouse_role" {
  count = var.deploy_clickhouse ? 1 : 0
  name  = var.clickhouse_iam_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { AWS = clickhouse_service.service[0].iam_role },
      Action    = "sts:AssumeRole"
    }]
  })
}

# Attach the S3 access policy to the role
resource "aws_iam_role_policy_attachment" "clickhouse_s3_access" {
  count      = length(aws_iam_role.clickhouse_role) > 0 ? 1 : 0
  role       = aws_iam_role.clickhouse_role[0].name
  policy_arn = aws_iam_policy.clickhouse_s3_access.arn
}

# IAM is eventually consistent across AWS's global infrastructure. Wait
# before the ClickPipe attempts to assume the role.
resource "time_sleep" "wait_for_iam_propagation" {
  count           = var.deploy_clickhouse ? 1 : 0
  depends_on      = [aws_iam_role_policy_attachment.clickhouse_s3_access]
  create_duration = "300s"
}

###############################
// S3 ClickPipe Resource (batch VPC Flow Logs pipeline)
// ---------------------------------------------------------------------
// Continuously polls the S3 bucket for new VPC Flow Log Parquet files
// and ingests them into the vpc_flow_logs table in ClickHouse.
//
// Note: In provider v3.x the `state` attribute is read-only and the
// `description` field has been removed; a ClickPipe is Running by default.
// Use `stopped = true` to pause a pipe.
###############################
resource "clickhouse_clickpipe" "vpc_flow_logs" {
  count = var.deploy_clickhouse && var.deploy_clickpipe ? 1 : 0
  name  = "VPC Flow Logs Pipeline"

  service_id = clickhouse_service.service[0].id

  source = {
    object_storage = {
      type           = "s3"
      format         = var.clickpipe_format
      url            = "s3://${var.deploy_s3 ? aws_s3_bucket.flow_logs[0].bucket : var.s3_bucket_name}/**"
      authentication = "IAM_ROLE"
      iam_role       = aws_iam_role.clickhouse_role[0].arn
      is_continuous  = var.clickpipe_is_continuous
    }
  }

  destination = {
    table         = var.clickpipe_table_name
    managed_table = true

    table_definition = {
      engine = {
        type = "MergeTree"
      }
    }

    columns = var.clickpipe_columns
  }

  depends_on = [time_sleep.wait_for_iam_propagation]
}

###############################
// Outputs
// ---------------------------------------------------------------------
// Output values for reference
###############################
# VPC and S3 outputs
# output "vpc_id" {
#   description = "The VPC ID (either newly created or provided)"
#   value       = var.deploy_vpc ? aws_vpc.main[0].id : var.vpc_id
# }

# output "s3_bucket_name" {
#   description = "The name of the S3 bucket"
#   value       = var.deploy_s3 ? aws_s3_bucket.flow_logs[0].bucket : var.s3_bucket_name
# }

# output "s3_bucket_arn" {
#   description = "The ARN of the S3 bucket for flow logs"
#   value       = var.deploy_s3 ? aws_s3_bucket.flow_logs[0].arn : var.s3_bucket_arn
# }
# output "flow_log_id" {
#   description = "The ID of the VPC Flow Log"
#   value       = var.deploy_flow_logs ? aws_flow_log.vpc_flow_logs[0].id : "Not created"
# }

# # ClickHouse outputs
# output "clickhouse_service_id" {
#   description = "The ID of the ClickHouse service"
#   value       = var.deploy_clickhouse ? clickhouse_service.service[0].id : "Not deployed"
# }

# output "clickhouse_hostname" {
#   description = "The hostname of the ClickHouse service"
#   value       = var.deploy_clickhouse ? clickhouse_service.service[0].endpoints[0].host : "Not deployed"
# }

# output "clickhouse_service_iam_role" {
#   description = "The IAM role ARN from ClickHouse service"
#   value       = var.deploy_clickhouse ? clickhouse_service.service[0].iam_role : null
# }

# # IAM outputs
# output "clickhouse_s3_access_role_arn" {
#   description = "The ARN of the IAM role for ClickHouse to access S3"
#   value       = length(aws_iam_role.clickhouse_role) > 0 ? aws_iam_role.clickhouse_role[0].arn : null
# }

# # ClickPipe outputs
# output "clickpipe_id" {
#   description = "The ID of the ClickPipe"
#   value       = length(clickhouse_clickpipe.vpc_flow_logs) > 0 ? clickhouse_clickpipe.vpc_flow_logs[0].id : null
# }

# output "clickpipe_status" {
#   description = "The status of the ClickPipe"
#   value       = length(clickhouse_clickpipe.vpc_flow_logs) > 0 ? clickhouse_clickpipe.vpc_flow_logs[0].state : null
# }

# # Sample log file output
# output "sample_log_file_path" {
#   description = "The S3 path to the sample VPC flow log file"
#   value       = var.deploy_s3 ? "s3://${aws_s3_bucket.flow_logs[0].bucket}/AWSLogs/sample-flow-log.log.gz" : null
# }
