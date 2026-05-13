# AWS Logs to ClickHouse Cloud — Batch + Streaming Demo

This project demonstrates two end-to-end log ingestion patterns into ClickHouse Cloud:

1. **Batch pipeline** — VPC Flow Logs land in S3 as Parquet, and an S3 ClickPipe continuously polls and ingests them into the `vpc_flow_logs` table.
2. **Streaming pipeline** — Application logs from an EC2 simulator flow to CloudWatch Logs, a subscription filter triggers a Lambda transformer that decompresses the CloudWatch envelope and PutRecords each event onto a Kinesis Data Stream, and a Kinesis ClickPipe ingests records in real time into the `cloudwatch_logs` table.

Both pipelines share a single ClickHouse Cloud service and the same EC2 simulator. Each pipeline can be enabled or disabled independently via deployment flags.

## Prerequisites

- AWS CLI installed and configured (used for provider authentication; no IAM trust policies are written via the CLI — all IAM is managed declaratively by Terraform)
- Terraform v1.10.0 or later
- An AWS account with permissions to manage VPC, EC2, S3, IAM, CloudWatch Logs, Kinesis, and Lambda
- A ClickHouse Cloud account and API credentials (organization ID, token key, token secret)

## AWS Profile Configuration

By default, `main.tf` uses `profile = "sa"`. If you want to use a different profile name, edit the `provider "aws"` block in `main.tf` and change the `profile` value.

```hcl
provider "aws" {
  region  = var.aws_region
  profile = "your-profile-name"  # change "sa" to your AWS CLI/SSO profile
}
```

Alternatively, omit `profile` entirely and rely on the `AWS_PROFILE` environment variable or default credential chain:

```hcl
provider "aws" {
  region = var.aws_region
}
```

```bash
export AWS_PROFILE=your-profile-name
terraform plan -var-file=terraform.tfvars -var-file=secret.tfvars
```

## Repository Structure

```
.
├── main.tf                              # Shared resources: providers, VPC, S3, Flow Logs,
│                                          ClickHouse service, IAM for S3 ClickPipe, S3 ClickPipe
├── cloudwatch_logs.tf                   # Streaming pipeline: CW Logs, Kinesis stream, Lambda,
│                                          IAM for Kinesis ClickPipe, Kinesis ClickPipe
├── ec2_log_simulator.tf                 # Subnet, IGW, SG, EC2 simulator, simulator IAM profile
├── ec2_simulator_user_data.sh.tftpl     # User-data template (traffic gen + awslogs config)
├── lambda/
│   └── cw_to_kinesis.py                 # Lambda that decompresses CW envelopes -> Kinesis
├── variables.tf                         # Variable declarations for both pipelines
├── outputs.tf                           # Output declarations for both pipelines
├── terraform.tfvars.example             # Example values for all non-sensitive variables
├── secret.tfvars.example                # Example values for sensitive variables
├── docs/
│   └── iam-trust.md                     # IAM trust reference: flows, permission tables, drift
└── .gitignore
```

## Provider Versions

| Provider                  | Version   | Notes                                                |
| ------------------------- | --------- | ---------------------------------------------------- |
| `hashicorp/aws`           | `~> 5.0`  |                                                      |
| `ClickHouse/clickhouse`   | `~> 3.14` | v3.14 is the GA release for ClickPipes via Terraform |
| `hashicorp/time`          | `~> 0.9`  | Used for IAM propagation delays                      |
| `hashicorp/archive`       | `~> 2.4`  | Used to zip the Lambda transformer                   |

**Breaking changes vs. the previous `2.2.0-alpha2` pin**:
- `clickhouse_clickpipe.description` was removed (top-level `description` attribute no longer exists).
- `clickhouse_clickpipe.state` is now read-only; use `stopped = true` to pause a pipe (default is running).
- `clickhouse_service.endpoints` is now an object (`endpoints.https.host`), not a list (`endpoints[0].host`).

## Architecture

### Batch pipeline — VPC Flow Logs

```
┌──────────────┐    ┌─────────────────┐    ┌──────────────┐
│ EC2 Simulator│───►│ VPC Flow Logs   │───►│ S3 (Parquet, │
│ (HTTP traffic│    │ (all traffic,   │    │  hourly parts)│
│  to example) │    │  ACCEPT+REJECT) │    │              │
└──────────────┘    └─────────────────┘    └───────┬──────┘
                                                   │
                                                   ▼
                                           ┌──────────────┐
                                           │ S3 ClickPipe │
                                           │ (IAM_ROLE)   │
                                           └───────┬──────┘
                                                   │
                                                   ▼
                                           ┌──────────────┐
                                           │ ClickHouse   │
                                           │ Cloud        │
                                           │ (vpc_flow_   │
                                           │  logs table) │
                                           └──────────────┘
```

### Streaming pipeline — CloudWatch Logs

```
┌──────────────┐    ┌─────────────────┐    ┌────────────────┐
│ EC2 Simulator│───►│ /var/log/app/   │───►│ CloudWatch Logs│
│ (JSON log    │    │ app.log         │    │ group          │
│  writer)     │    │ (awslogs agent) │    │                │
└──────────────┘    └─────────────────┘    └────────┬───────┘
                                                    │ subscription filter
                                                    ▼
                                           ┌────────────────┐
                                           │ Lambda         │
                                           │ cw_to_kinesis  │
                                           │ (gunzip, fan   │
                                           │  out events)   │
                                           └────────┬───────┘
                                                    │ PutRecords
                                                    ▼
                                           ┌────────────────┐
                                           │ Kinesis Data   │
                                           │ Stream         │
                                           └────────┬───────┘
                                                    │
                                                    ▼
                                           ┌────────────────┐
                                           │ Kinesis        │
                                           │ ClickPipe      │
                                           │ (IAM_ROLE)     │
                                           └────────┬───────┘
                                                    │
                                                    ▼
                                           ┌────────────────┐
                                           │ ClickHouse     │
                                           │ Cloud          │
                                           │ (cloudwatch_   │
                                           │  logs table)   │
                                           └────────────────┘
```

### Why the Lambda transformer

CloudWatch Logs subscription filters always emit **gzip-compressed payloads** that wrap N log events in a single JSON envelope:

```json
{
  "messageType": "DATA_MESSAGE",
  "owner": "<account-id>",
  "logGroup": "/apac-sa-demo/app",
  "logStream": "<instance-id>",
  "subscriptionFilters": ["cw-to-lambda-transformer"],
  "logEvents": [
    { "id": "...", "timestamp": 1715000000000, "message": "..." },
    ...
  ]
}
```

ClickPipe's Kinesis source expects clean `JSONEachRow` records. The Lambda (`lambda/cw_to_kinesis.py`) sits between the subscription filter and the Kinesis stream:

1. Receives the subscription event from CloudWatch Logs.
2. Base64-decodes and gunzips the payload.
3. Skips `CONTROL_MESSAGE` (CloudWatch health-check pings).
4. Flattens each `logEvent` into a single JSON line and writes it to Kinesis via `PutRecords` (batched up to 500 records per call).

The records on the Kinesis stream therefore look like:

```json
{"log_group":"...","log_stream":"...","owner":"...","timestamp":1715000000000,"id":"...","message":"<original log line>"}
```

…which ClickPipe ingests directly with `format = JSONEachRow` and no further decoding.

## IAM Trust Configuration

Cross-account IAM trust between AWS and ClickHouse Cloud is configured **entirely by Terraform**.

For the full walkthrough — step-by-step flow, permission policy tables for both pipelines, naming convention, drift recovery, and design rationale — see [`docs/iam-trust.md`](docs/iam-trust.md).

## Quick Start

1. Clone and initialize:
   ```bash
   git clone https://github.com/ClickHouse/aws_vpc_logs_demo.git
   cd aws_vpc_logs_demo
   terraform init
   ```

2. Configure AWS credentials. The Terraform AWS provider in `main.tf` uses `profile = "sa"`. Choose one of these options:

   **Option A: AWS SSO (for users with SSO access)**
   ```bash
   aws configure sso
   export AWS_PROFILE=sa
   export AWS_CONFIG_FILE=$HOME/.aws/config
   ```

   **Option B: AWS Access Keys (for external partners without SSO)**
   
   Create an AWS IAM user with programmatic access if you don't have one. Then:
   ```bash
   aws configure --profile sa
   # Interactively enter:
   #   AWS Access Key ID: <your-access-key-id>
   #   AWS Secret Access Key: <your-secret-access-key>
   #   Default region: <same as your aws_region in terraform.tfvars>
   #   Default output format: json
   
   export AWS_PROFILE=sa
   export AWS_CONFIG_FILE=$HOME/.aws/config
   ```

   **Option C: Environment variables (for CI/CD or automation)**
   ```bash
   export AWS_ACCESS_KEY_ID=<your-access-key-id>
   export AWS_SECRET_ACCESS_KEY=<your-secret-access-key>
   export AWS_DEFAULT_REGION=<same as aws_region in terraform.tfvars>
   # Skip AWS_PROFILE; Terraform will use env vars by default
   ```
   
   > **IAM Permissions Note**: The deploying user/profile must have permissions for: VPC, EC2, S3, CloudWatch Logs, Kinesis, Lambda, IAM (creating roles and policies), and CloudFormation. Work with your AWS admin to scope a least-privilege policy if needed.

3. Copy and edit the example variable files:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   cp secret.tfvars.example secret.tfvars
   # edit both — fill in AWS region, bucket name, ClickHouse org ID, token, etc.
   ```

   **`secret.tfvars` contents and where to obtain each value:**

   | Variable           | What it is                                              | Where to obtain                                                                                                                                                                                                       |
   | ------------------ | ------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
   | `organization_id`  | The UUID of your ClickHouse Cloud organization          | ClickHouse Cloud console → top-left org switcher → **Organization details**. Or any service URL contains it: `https://console.clickhouse.cloud/organizations/<org-id>/...`                                            |
   | `token_key`        | The "Key ID" half of a ClickHouse Cloud API key pair    | ClickHouse Cloud console → **Settings** → **API keys** → **New API key**. Give it the `Admin` role (needed to provision services and ClickPipes). The Key ID is shown once on creation.                               |
   | `token_secret`     | The "Secret" half of the API key pair                   | Shown only once at API key creation alongside the Key ID. Store it immediately — the console will not show it again. If you lose it, revoke the key and create a new pair.                                            |
   | `service_password` | The password for the ClickHouse service's `default` user | Choose any strong value yourself; this Terraform applies it when provisioning the service. Use it to connect via `clickhouse-client`, JDBC, or the SQL console. Treat it as sensitive — never commit to git.          |

   Keep `secret.tfvars` out of version control (`.gitignore` already excludes `*.tfvars` except `*.tfvars.example`).

4. Deploy:
   ```bash
   terraform plan  -var-file=terraform.tfvars -var-file=secret.tfvars
   terraform apply -var-file=terraform.tfvars -var-file=secret.tfvars
   ```

5. Wait for both pipelines to start producing data:
   - VPC Flow Logs take 3–5 minutes to land in S3 after the simulator starts.
   - The streaming pipeline begins delivering events to ClickHouse within ~5–10 seconds of the simulator writing its first log line, once the 300s IAM propagation wait completes.

## Querying

### Batch pipeline — `vpc_flow_logs`

```sql
-- Top source IPs by traffic volume
SELECT srcaddr, SUM(bytes) AS total_bytes, COUNT(*) AS connection_count
FROM vpc_flow_logs
GROUP BY srcaddr
ORDER BY total_bytes DESC
LIMIT 10;

-- Traffic by protocol
SELECT protocol, SUM(bytes) AS total_bytes
FROM vpc_flow_logs
GROUP BY protocol
ORDER BY total_bytes DESC;
```

### Streaming pipeline — `cloudwatch_logs`

```sql
-- Most recent application log events
SELECT
    fromUnixTimestamp64Milli(timestamp) AS ts,
    log_stream,
    message
FROM cloudwatch_logs
ORDER BY ts DESC
LIMIT 20;

-- Parse the JSON message column into structured fields
SELECT
    fromUnixTimestamp64Milli(timestamp)        AS ts,
    JSONExtractString(message, 'request_id')   AS request_id,
    JSONExtractInt(message, 'http_code')       AS http_code,
    JSONExtractInt(message, 'latency_ms')      AS latency_ms,
    JSONExtractString(message, 'status')       AS status
FROM cloudwatch_logs
ORDER BY ts DESC
LIMIT 20;

-- p95 latency over the last 5 minutes
SELECT quantile(0.95)(JSONExtractInt(message, 'latency_ms')) AS p95_ms
FROM cloudwatch_logs
WHERE fromUnixTimestamp64Milli(timestamp) > now() - INTERVAL 5 MINUTE;
```

## Deployment Flags

| Flag                          | Default | Pipeline   | Purpose                                                       |
| ----------------------------- | ------- | ---------- | ------------------------------------------------------------- |
| `deploy_vpc`                  | `true`  | Shared     | Create new VPC vs. use existing                               |
| `deploy_s3`                   | `true`  | Batch      | Create new S3 bucket for VPC Flow Logs vs. use existing       |
| `deploy_flow_logs`            | `true`  | Batch      | Enable VPC Flow Logs capture                                  |
| `deploy_simulator`            | `true`  | Shared     | Deploy the EC2 traffic generator                              |
| `deploy_clickhouse`           | `true`  | Shared     | Provision the ClickHouse Cloud service                        |
| `deploy_clickpipe`            | `true`  | Batch      | Create the S3 ClickPipe (`vpc_flow_logs` table)               |
| `deploy_cloudwatch_logs`      | `false` | Streaming  | Create the CloudWatch Logs group & EC2 instance profile       |
| `deploy_kinesis_stream`       | `false` | Streaming  | Create the Kinesis Data Stream                                |
| `deploy_lambda_transformer`   | `false` | Streaming  | Create the Lambda + subscription filter                       |
| `deploy_cloudwatch_clickpipe` | `false` | Streaming  | Create the Kinesis ClickPipe (`cloudwatch_logs` table)        |

To enable the streaming pipeline end-to-end, set all four streaming flags to `true` (as shown in `terraform.tfvars.example`).

## Cleanup

```bash
terraform destroy -var-file=terraform.tfvars -var-file=secret.tfvars
```

## Troubleshooting

### Batch pipeline (S3 ClickPipe)

- ClickPipe state stuck in `Provisioning` or showing `AccessDenied`: verify the trust policy on `ClickHouseAccess-ClickPipe-S3-Demo` references the current `clickhouse_service.service.iam_role` ARN.
- No data in `vpc_flow_logs`: VPC Flow Logs take 3–5 minutes to first land in S3; verify S3 bucket has Parquet objects under `AWSLogs/`.

### Streaming pipeline (Kinesis ClickPipe)

- **ClickPipe shows `Failed` / `AccessDenied`** — the trust policy on `ClickHouseAccess-ClickPipe-Kinesis-Demo` is the most likely cause. Run:
  ```bash
  aws iam get-role --role-name ClickHouseAccess-ClickPipe-Kinesis-Demo \
    --query 'Role.AssumeRolePolicyDocument'
  ```
  The principal should equal the value of the `clickhouse_service_iam_role` output. If they differ, the ClickHouse service was likely recreated out-of-band — `terraform apply` will reconcile it because the AWS IAM role depends on `clickhouse_service.service[0].iam_role` and Terraform will detect the drift.
- **CloudWatch Logs group is empty** — the EC2 simulator isn't shipping logs. SSH in and check `journalctl -u awslogsd` and `cat /var/log/app/app.log`. Verify the instance profile is attached (`aws ec2 describe-instances --instance-ids <id> --query 'Reservations[].Instances[].IamInstanceProfile'`).
- **Log group has events but Kinesis stream is empty** — the Lambda isn't being invoked. Check CloudWatch metrics for the Lambda function (`Invocations`, `Errors`) and the Lambda's own log group `/aws/lambda/apac-sa-demo-cw-to-kinesis`.
- **Kinesis stream has records but the ClickPipe table is empty** — the ClickPipe role can't read from the stream. Test by assuming the role manually:
  ```bash
  aws sts assume-role \
    --role-arn $(terraform output -raw clickhouse_kinesis_role_arn) \
    --role-session-name debug
  ```
  Then with the temporary credentials, run `aws kinesis describe-stream --stream-name apac-sa-demo-log-stream`.

### IAM propagation timing

If apply consistently fails on `clickhouse_clickpipe.cloudwatch_logs` with an IAM error, increase `time_sleep.wait_for_kinesis_iam_propagation.create_duration` (and the matching S3 one in `main.tf`) past 300 seconds. AWS does not document a deterministic upper bound for IAM propagation.

## Notes

- The S3 ClickPipe and Kinesis ClickPipe share the same ClickHouse Cloud service but use **separate** customer-owned IAM roles. Don't combine them; keep the blast radius small per pipeline.
- The Lambda transformer is intentionally minimal (~60 lines). Add a CloudWatch alarm on the function's `Errors` metric in production.
- All IAM roles in this demo use a permission boundary of "minimum required actions only." If you reuse these in production, scope the resources further (e.g. by stream name pattern or log group prefix).

## To Do

- [x] Add ClickHouse integration steps
- [x] Add streaming pipeline via CloudWatch Logs + Kinesis
- [ ] Add Grafana dashboard
- [x] Clean up the Terraform code
- [ ] Add CloudWatch alarms for Lambda errors and Kinesis throttling
