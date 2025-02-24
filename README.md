# VPC Flow Logs to Clickhouse Cloud Demo

This project demonstrates how to export AWS VPC Flow Logs to S3 and subsequently ingest them into Clickhouse Cloud. It includes Terraform configurations to set up the necessary AWS infrastructure and a traffic simulator for testing purposes.

## Prerequisites

- AWS CLI installed and configured with appropriate credentials
- Terraform v1.10.0 or later
- An AWS account with appropriate permissions
- A Clickhouse Cloud account (for log ingestion)

## Project Structure

```
.
├── main.tf                 # Main Terraform configuration
├── variables.tf            # Variable definitions
├── outputs.tf             # Output definitions
├── ec2_log_simulator.tf   # EC2 instance for traffic simulation
└── .gitignore            # Git ignore file
```

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

4. Review and modify variables:

- Copy `terraform.tfvars.example` to `terraform.tfvars` (if provided)
- Adjust variables according to your needs

5. Deploy the infrastructure:

```bash
terraform plan    # Review the changes
terraform apply   # Apply the changes
```

## Configuration Options

The project supports various deployment scenarios through variables:

- `deploy_vpc`: Create a new VPC (true/false)
- `deploy_s3`: Create a new S3 bucket (true/false)
- `deploy_flow_logs`: Enable VPC Flow Logs (true/false)
- `deploy_simulator`: Deploy EC2 traffic simulator (true/false)

## Components

### VPC Flow Logs

- Captures network traffic in your VPC
- Configurable aggregation intervals
- Logs stored in S3 bucket

### S3 Bucket

- Secure storage for VPC Flow Logs
- Versioning enabled
- Configurable public/private access

### EC2 Traffic Simulator

- Generates sample network traffic
- Runs on Amazon Linux 2
- Automatically sends HTTP requests to generate flow logs

## Development

### Making Changes

1. Create a new branch:

```bash
git checkout -b feature/your-feature-name
```

2. Make your changes to the Terraform configurations

3. Test your changes:

```bash
terraform fmt     # Format the code
terraform validate # Validate the configuration
terraform plan    # Review changes
```

4. Commit your changes:

```bash
git add .
git commit -m "Description of your changes"
```

### Best Practices

- Always format your Terraform code using `terraform fmt`
- Use meaningful variable names and descriptions
- Add tags to resources for better organization
- Keep sensitive information in variables and never commit them

## Clickhouse Integration

After setting up the infrastructure:

1. Configure Clickhouse Cloud to read from the S3 bucket
2. Set up the appropriate table schema for VPC Flow Logs
3. Create a data pipeline to continuously ingest logs

(Detailed Clickhouse integration steps to be added)

## Cleanup

To destroy the infrastructure:

```bash
terraform destroy
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## Security Considerations

- The EC2 simulator allows SSH access from any IP (0.0.0.0/0) - modify for production
- S3 bucket public access is configurable - ensure appropriate settings for your use case
- Review and adjust IAM permissions as needed

## Support

Create a new issue in the repository!

## To Do

- [ ] Add Clickhouse Integration Steps
- [ ] Add Grafana Dashboard
- [ ] Clean up the Terraform code
