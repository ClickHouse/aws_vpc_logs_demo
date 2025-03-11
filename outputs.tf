# VPC and S3 outputs
output "vpc_id" {
  description = "The VPC ID (either newly created or provided)"
  value       = var.deploy_vpc ? aws_vpc.main[0].id : var.vpc_id
}

output "s3_bucket_name" {
  description = "The name of the S3 bucket"
  value       = var.deploy_s3 ? aws_s3_bucket.flow_logs[0].bucket : var.s3_bucket_name
}

output "s3_bucket_arn" {
  description = "The ARN of the S3 bucket for flow logs"
  value       = var.deploy_s3 ? aws_s3_bucket.flow_logs[0].arn : var.s3_bucket_arn
}

output "flow_log_id" {
  description = "The ID of the VPC Flow Log"
  value       = var.deploy_flow_logs ? aws_flow_log.vpc_flow_logs[0].id : "Not created"
}

# ClickHouse outputs
output "clickhouse_service_id" {
  description = "The ID of the ClickHouse service"
  value       = var.deploy_clickhouse ? clickhouse_service.service[0].id : "Not deployed"
}

output "clickhouse_hostname" {
  description = "The hostname of the ClickHouse service"
  value       = var.deploy_clickhouse ? clickhouse_service.service[0].endpoints[0].host : "Not deployed"
}

output "clickhouse_service_iam_role" {
  description = "The IAM role ARN from ClickHouse service"
  value       = var.deploy_clickhouse ? clickhouse_service.service[0].iam_role : null
}

# IAM outputs
output "clickhouse_s3_access_role_arn" {
  description = "The ARN of the IAM role for ClickHouse to access S3"
  value       = length(aws_iam_role.clickhouse_role) > 0 ? aws_iam_role.clickhouse_role[0].arn : null
}

# ClickPipe outputs
output "clickpipe_id" {
  description = "The ID of the ClickPipe"
  value       = length(clickhouse_clickpipe.vpc_flow_logs) > 0 ? clickhouse_clickpipe.vpc_flow_logs[0].id : null
}

output "clickpipe_status" {
  description = "The status of the ClickPipe"
  value       = length(clickhouse_clickpipe.vpc_flow_logs) > 0 ? clickhouse_clickpipe.vpc_flow_logs[0].state : null
}

# Sample log file output
output "sample_log_file_path" {
  description = "The S3 path to the sample VPC flow log file"
  value       = var.deploy_s3 ? "s3://${aws_s3_bucket.flow_logs[0].bucket}/AWSLogs/sample-flow-log.log.gz" : null
} 