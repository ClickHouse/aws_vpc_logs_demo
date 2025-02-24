// outputs.tf
// ---------------------------------------------------------------------
// This file defines outputs to make it easy to reference deployed resources.
// ---------------------------------------------------------------------

// VPC ID output (either newly created or provided)
output "vpc_id" {
  description = "The VPC ID (either newly created or provided)"
  value       = var.deploy_vpc ? aws_vpc.main[0].id : var.vpc_id
}

// S3 Bucket ARN output
output "s3_bucket_arn" {
  description = "The ARN of the S3 bucket for flow logs"
  value       = var.deploy_s3 ? aws_s3_bucket.flow_logs[0].arn : var.s3_bucket_arn
}

// Flow Log ID output
output "flow_log_id" {
  description = "The ID of the VPC Flow Log"
  value       = var.deploy_flow_logs ? aws_flow_log.vpc_flow_logs[0].id : "Not created"
}

// EC2 Instance ID for the simulator.
output "simulator_instance_id" {
  description = "The ID of the EC2 instance generating traffic"
  value       = var.deploy_simulator ? aws_instance.simulator[0].id : "Not deployed"
}