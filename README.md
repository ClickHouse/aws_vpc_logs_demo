# VPC Flow Logs to ClickHouse Cloud

This project demonstrates how to export AWS VPC Flow Logs to S3 and subsequently ingest them into ClickHouse Cloud. It includes Terraform configurations to set up the necessary AWS infrastructure and a traffic simulator for testing purposes.

## Prerequisites

- AWS CLI installed and configured with appropriate credentials
- Terraform v1.10.0 or later
- An AWS account with appropriate permissions
- A ClickHouse Cloud account (for log ingestion)
- ClickHouse Cloud API credentials (organization ID, token key, and token secret)

## Repository Structure

```
.
├── main.tf                   # Main Terraform configuration for all resources
├── ec2_log_simulator.tf      # EC2 instance for traffic simulation
├── variables.tf              # Variable definitions
├── terraform.tfvars.example  # Example variable values
├── secret.tfvars.example     # Example for sensitive variables
└── .gitignore                # Git ignore file
```

## Components

### 1. VPC and Networking (main.tf, ec2_log_simulator.tf)

- Creates a new VPC with public subnet
- Sets up Internet Gateway and route tables
- Configurable via deployment flags

### 2. S3 Bucket (main.tf)

- Secure storage for VPC Flow Logs
- Versioning enabled
- Configurable public/private access
- Bucket policies for log delivery

### 3. VPC Flow Logs (main.tf)

- Captures network traffic in your VPC
- Configurable aggregation intervals
- Logs stored in S3 bucket

### 4. EC2 Traffic Simulator (ec2_log_simulator.tf)

- Generates sample network traffic
- Runs on Amazon Linux 2
- Automatically sends HTTP requests to generate flow logs
- Deployed as a systemd service

### 5. ClickHouse Cloud Integration (main.tf)

- Automatically provisions a ClickHouse Cloud service
- Creates a ClickPipe to ingest VPC Flow Logs from S3
- Configurable service tier and resources
- Supports idle scaling to optimize costs

### 6. IAM Integration (main.tf)

- Creates IAM policy for S3 access
- Sets up IAM role for ClickHouse to assume
- Establishes trust relationship between AWS and ClickHouse

## Resource Dependencies and Execution Flow

The resources in this project have the following dependencies:

1. **VPC and Networking**

   - VPC is created first
   - Followed by subnet, internet gateway, and route tables

2. **S3 Bucket**

   - Created independently of VPC
   - Bucket policy depends on bucket creation

3. **VPC Flow Logs**

   - Depends on both VPC and S3 bucket
   - Configured to send logs to the S3 bucket

4. **EC2 Traffic Simulator**

   - Depends on VPC, subnet, and security group
   - Generates traffic that produces flow logs

5. **ClickHouse Service**

   - Created independently of AWS resources
   - Requires ClickHouse Cloud API credentials

6. **IAM Integration**

   - IAM policy depends on S3 bucket
   - IAM role depends on ClickHouse service creation (to get the role ARN)

7. **ClickPipe**
   - Depends on ClickHouse service and IAM role
   - Connects S3 bucket to ClickHouse for data ingestion

## Quick Start

1. Clone the repository:

```bash
git clone https://github.com/ClickHouse/aws_vpc_logs_demo.git
cd aws_vpc_logs_demo
```

2. Initialize Terraform:

```bash
terraform init
```

3. Configure your AWS credentials:

```bash
aws configure sso
# make sure to set the profile to "sa" OR update the profile name in the main.tf file
# Update the Bash Profile or Zsh Profile to set the AWS_PROFILE and AWS_CONFIG_FILE environment variables
export AWS_PROFILE=sa
export AWS_CONFIG_FILE=$HOME/.aws/config
```

4. Create a `terraform.tfvars` file with your configuration:

```hcl
# AWS Configuration
aws_region = "ap-southeast-1"

# ClickHouse Cloud credentials
organization_id = "your-organization-id"
token_key       = "your-token-key"
token_secret    = "your-token-secret"
service_password = "your-secure-password"

# Deployment flags
deploy_vpc = true
deploy_s3 = true
deploy_flow_logs = true
deploy_simulator = true
deploy_clickhouse = true
deploy_clickpipe = true

# S3 Bucket configuration
s3_bucket_name = "your-globally-unique-bucket-name"
s3_bucket_private = true

# ClickHouse configuration
clickhouse_service_name = "VPCFlowLogs"
clickhouse_region = "ap-southeast-2"
clickhouse_iam_role_name = "ClickHouseS3AccessRole"
```

5. Deploy the infrastructure:

```bash
terraform plan    # Review the changes
terraform apply   # Apply the changes
```

## Querying VPC Flow Logs in ClickHouse

Once the infrastructure is deployed, you can query your VPC Flow Logs using SQL:

```sql
-- Example: Top source IPs by traffic volume
SELECT
    srcaddr,
    SUM(bytes) AS total_bytes,
    COUNT(*) AS connection_count
FROM vpc_flow_logs
GROUP BY srcaddr
ORDER BY total_bytes DESC
LIMIT 10;

-- Example: Traffic by protocol
SELECT
    protocol,
    SUM(bytes) AS total_bytes
FROM vpc_flow_logs
GROUP BY protocol
ORDER BY total_bytes DESC;
```

## Cleanup

To destroy the infrastructure:

```bash
terraform destroy
```

## Notes

- The project uses a single Terraform configuration file (main.tf) for all resources except the EC2 simulator
- All outputs are defined in the main.tf file
- The ClickPipe resource depends on the ClickHouse service and IAM role, which is managed through dependencies
- The IAM role trust policy is updated using a local-exec provisioner to ensure proper permissions

## Troubleshooting

If you encounter issues with the ClickPipe not being able to access the S3 bucket:

1. Verify that the IAM role has the correct trust policy
2. Check that the S3 bucket policy allows access from the ClickHouse service
3. Ensure that the ClickHouse service has the correct IAM role ARN
4. Wait for IAM propagation (can take up to 5 minutes)

For more detailed troubleshooting, check the AWS CloudTrail logs and ClickHouse Cloud logs.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## Support

Create a new issue in the repository!

## To Do

- [x] Add Clickhouse Integration Steps
- [ ] Add Grafana Dashboard
- [ ] Clean up the Terraform code
