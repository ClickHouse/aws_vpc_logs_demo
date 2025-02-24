// main.tf
// ---------------------------------------------------------------------
// Provider configuration and resource definitions.
// This file instantiates the VPC, S3 bucket, and VPC Flow Logs resources
// based on the boolean flags defined in variables.tf.
// ---------------------------------------------------------------------

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  profile = "sa"
}

###############################
// VPC Resource
// ---------------------------------------------------------------------
// Create a new VPC if the flag "deploy_vpc" is true.
// If false, the user must supply an existing VPC ID via var.vpc_id.
###############################
resource "aws_vpc" "main" {
  count              = var.deploy_vpc ? 1 : 0
  cidr_block         = var.vpc_cidr
  enable_dns_support = true
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
  force_destroy = true  # This deletes all objects in the bucket when the bucket is destroyed, use for dev and testing only

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
  count  = var.deploy_s3 ? 1 : 0  # Always create policy for Flow Logs
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
  log_destination      = var.deploy_s3 ? aws_s3_bucket.flow_logs[0].arn : var.s3_bucket_arn
  log_destination_type = "s3"
  traffic_type         = var.flow_logs_traffic_type
#   log_format           = var.flow_logs_log_format
  max_aggregation_interval = var.max_aggregation_interval
  tags = {
    Name = "apac-sa-demo-flow-logs"
  }
}