# IAM Trust Configuration Reference

This document explains how cross-account IAM trust is set up between AWS and ClickHouse Cloud for the two ClickPipes in this project. It is reference material — you do **not** need to read or apply anything here manually. All IAM resources are managed declaratively by Terraform, and `terraform apply` configures them end-to-end.

If a ClickPipe shows `Failed` / `AccessDenied`, see the **Troubleshooting** section in the [main README](../README.md#troubleshooting) first.

## Overview

Both ClickPipes use cross-account IAM trust: ClickHouse Cloud runs in its own AWS account and assumes a role you own in your AWS account. The trust policy on the customer-owned role must allow the IAM role ARN that ClickHouse Cloud exposes on the service resource (`clickhouse_service.iam_role`).

This project sets the trust policy declaratively, inline, on the customer-owned role — no shell-outs, no `aws iam update-assume-role-policy`, no manual steps. Terraform's dependency graph guarantees that the ClickHouse service is provisioned **before** the AWS IAM role is created, so the service ARN is always known at the moment the trust policy is written.

## Step-by-step (per pipeline)

1. **Provision the ClickHouse service** (`clickhouse_service.service`). The service exposes `iam_role`, which is the ARN of the role ClickHouse Cloud uses internally to assume your role. Terraform schedules this first because the IAM role below references the output.
2. **Create the customer-owned IAM role** with the final trust policy inline:
   ```hcl
   resource "aws_iam_role" "clickhouse_role" {
     name = var.clickhouse_iam_role_name

     assume_role_policy = jsonencode({
       Version = "2012-10-17",
       Statement = [{
         Effect    = "Allow",
         Principal = { AWS = clickhouse_service.service[0].iam_role },
         Action    = "sts:AssumeRole"
       }]
     })
   }
   ```
   Attach the permission policy (`s3:Get*`/`s3:List*` for the batch pipeline, the Kinesis actions for the streaming pipeline).
3. **Wait for IAM to propagate** (`time_sleep`, 300s). IAM is eventually consistent across AWS's global infrastructure and the ClickPipe will fail with `AccessDenied` or `Role not found` if it tries to assume the role too early.
4. **Create the ClickPipe**. It assumes the customer-owned role, which is trusted to be assumed by the ClickHouse service role, which has the permission policy you attached.

The same pattern is implemented twice — once in [`main.tf`](../main.tf) (S3 access role: `aws_iam_role.clickhouse_role`) and once in [`cloudwatch_logs.tf`](../cloudwatch_logs.tf) (Kinesis access role: `aws_iam_role.clickhouse_kinesis_role`). Both roles are created *after* the ClickHouse service, so no bootstrap-then-rewrite dance is needed.

## Naming convention

ClickHouse Cloud recommends IAM role names begin with `ClickHouseAccess-`. Both demo roles follow this:

- S3 ClickPipe: `ClickHouseAccess-ClickPipe-S3-Demo`
- Kinesis ClickPipe: `ClickHouseAccess-ClickPipe-Kinesis-Demo`

## S3 permission policy

The S3 ClickPipe role is granted bucket-listing and object-read permissions on the demo bucket:

| Action                      | Resource                              |
| --------------------------- | ------------------------------------- |
| `s3:GetBucketLocation`      | `arn:aws:s3:::<bucket>`               |
| `s3:ListBucket`             | `arn:aws:s3:::<bucket>`               |
| `s3:Get*`                   | `arn:aws:s3:::<bucket>/*`             |
| `s3:List*`                  | `arn:aws:s3:::<bucket>/*`             |

Defined in [`main.tf`](../main.tf) as `aws_iam_policy.clickhouse_s3_access`.

## Kinesis permission policy

The Kinesis ClickPipe role is granted the minimum set of Kinesis actions required by ClickHouse Cloud (see the [official auth guide](https://clickhouse.com/docs/integrations/clickpipes/kinesis/auth)):

| Action                              | Resource                          |
| ----------------------------------- | --------------------------------- |
| `kinesis:DescribeStream`            | the stream ARN                    |
| `kinesis:GetShardIterator`          | the stream ARN                    |
| `kinesis:GetRecords`                | the stream ARN                    |
| `kinesis:ListShards`                | the stream ARN                    |
| `kinesis:RegisterStreamConsumer`    | the stream ARN                    |
| `kinesis:DeregisterStreamConsumer`  | the stream ARN                    |
| `kinesis:ListStreamConsumers`       | the stream ARN                    |
| `kinesis:SubscribeToShard`          | `<stream-arn>/*` (consumer scope) |
| `kinesis:DescribeStreamConsumer`    | `<stream-arn>/*` (consumer scope) |
| `kinesis:ListStreams`               | `*`                               |

`RegisterStreamConsumer` / `SubscribeToShard` / `DescribeStreamConsumer` are required only when `cloudwatch_clickpipe_use_enhanced_fan_out = true`. They're included unconditionally so flipping the flag doesn't require a separate IAM apply.

Defined in [`cloudwatch_logs.tf`](../cloudwatch_logs.tf) as `aws_iam_policy.clickhouse_kinesis_access`.

## Why an inline trust policy instead of a `local-exec` workaround?

An earlier version of this project bootstrapped each role with `Principal: { AWS: "*" }` and then overwrote the trust policy via a `null_resource` that shelled out to `aws iam update-assume-role-policy`. That worked but introduced unnecessary complexity:

- The runner needed the AWS CLI installed and `iam:UpdateAssumeRolePolicy` permission.
- The trust policy was opaque in `terraform plan` output — the final value only appeared after apply.
- The bootstrap policy briefly granted broad trust (mitigated by the fact that no permission policy was attached yet, but still noisy).

Terraform's dependency graph already orders resources correctly when one references another's output. By writing `Principal = { AWS = clickhouse_service.service[0].iam_role }` inline, Terraform automatically:

1. Creates the ClickHouse service first.
2. Reads its `iam_role` output.
3. Creates the AWS IAM role with the correct trust policy in a single shot.

No shell-outs, no bootstrap state, plan output shows the final trust policy.

## Drift recovery

If the ClickHouse service is ever recreated (e.g., a name change forces replacement), its `iam_role` ARN changes. Because the AWS IAM role's `assume_role_policy` depends on that value, Terraform detects the drift and updates the trust policy in place on the next `terraform apply`. No manual intervention is needed.

If you suspect drift, compare:

```bash
terraform output clickhouse_service_iam_role
aws iam get-role --role-name ClickHouseAccess-ClickPipe-Kinesis-Demo \
  --query 'Role.AssumeRolePolicyDocument.Statement[0].Principal.AWS'
```

If they differ, run `terraform apply` to reconcile.
