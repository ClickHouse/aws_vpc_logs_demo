// cloudwatch_logs.tf
// ---------------------------------------------------------------------
// Streaming pipeline: CloudWatch Logs -> Lambda transformer -> Kinesis
//                     Data Stream -> Kinesis ClickPipe -> ClickHouse.
//
// Why the Lambda transformer:
//   CloudWatch Logs subscription filters always emit gzip-compressed
//   payloads containing a JSON envelope with N log events. ClickPipe's
//   Kinesis source expects clean JSONEachRow records. The Lambda
//   decompresses each subscription event, unwraps the envelope, and
//   PutRecords each individual log event onto the Kinesis stream so
//   ClickPipe can ingest it directly without server-side decoding.
//
// All resources gate on var.deploy_cloudwatch_logs (and downstream
// flags) so the streaming pipeline can be enabled/disabled independently
// of the existing batch pipeline.
// ---------------------------------------------------------------------

###############################
// CloudWatch Log Group
// ---------------------------------------------------------------------
// Destination for the EC2 simulator's awslogs agent. Shared by any
// downstream consumer that wants AWS-side visibility into the same logs.
###############################
resource "aws_cloudwatch_log_group" "app_logs" {
  count             = var.deploy_cloudwatch_logs ? 1 : 0
  name              = var.cloudwatch_log_group_name
  retention_in_days = var.cloudwatch_log_retention_days

  tags = {
    Name = "apac-sa-demo-cw-logs"
  }
}

###############################
// Kinesis Data Stream
// ---------------------------------------------------------------------
// Buffers decompressed log events between the Lambda transformer and
// the Kinesis ClickPipe. ON_DEMAND mode is recommended for demos; switch
// to PROVISIONED with var.kinesis_shard_count for predictable cost.
###############################
resource "aws_kinesis_stream" "log_stream" {
  count            = var.deploy_kinesis_stream ? 1 : 0
  name             = var.kinesis_stream_name
  retention_period = var.kinesis_retention_hours

  // shard_count is only honored when stream_mode = PROVISIONED.
  shard_count = var.kinesis_stream_mode == "PROVISIONED" ? var.kinesis_shard_count : null

  stream_mode_details {
    stream_mode = var.kinesis_stream_mode
  }

  tags = {
    Name = "apac-sa-demo-kinesis"
  }
}

###############################
// Lambda Transformer
// ---------------------------------------------------------------------
// Bundled as a zip from lambda/cw_to_kinesis.py. The function receives
// the CloudWatch Logs subscription event, gunzips it, splits the bundled
// log events, and PutRecords each one onto the Kinesis stream.
###############################
data "archive_file" "cw_to_kinesis" {
  count       = var.deploy_lambda_transformer ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/lambda/cw_to_kinesis.py"
  output_path = "${path.module}/lambda/cw_to_kinesis.zip"
}

resource "aws_iam_role" "lambda_exec" {
  count = var.deploy_lambda_transformer ? 1 : 0
  name  = var.lambda_iam_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

// Standard Lambda basic execution permissions (CloudWatch Logs for the
// function's own logs).
resource "aws_iam_role_policy_attachment" "lambda_basic_exec" {
  count      = var.deploy_lambda_transformer ? 1 : 0
  role       = aws_iam_role.lambda_exec[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

// Allow the Lambda to PutRecord(s) on the Kinesis stream.
resource "aws_iam_role_policy" "lambda_kinesis_write" {
  count = var.deploy_lambda_transformer && var.deploy_kinesis_stream ? 1 : 0
  name  = "LambdaKinesisWritePolicy"
  role  = aws_iam_role.lambda_exec[0].id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = [
        "kinesis:PutRecord",
        "kinesis:PutRecords",
        "kinesis:DescribeStream"
      ],
      Resource = aws_kinesis_stream.log_stream[0].arn
    }]
  })
}

resource "aws_lambda_function" "cw_to_kinesis" {
  count            = var.deploy_lambda_transformer && var.deploy_kinesis_stream ? 1 : 0
  function_name    = var.lambda_function_name
  role             = aws_iam_role.lambda_exec[0].arn
  handler          = "cw_to_kinesis.lambda_handler"
  runtime          = "python3.11"
  filename         = data.archive_file.cw_to_kinesis[0].output_path
  source_code_hash = data.archive_file.cw_to_kinesis[0].output_base64sha256
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      DESTINATION_STREAM_NAME = aws_kinesis_stream.log_stream[0].name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_exec,
    aws_iam_role_policy.lambda_kinesis_write,
  ]

  tags = {
    Name = "apac-sa-demo-cw-to-kinesis"
  }
}

// Allow CloudWatch Logs (in this region) to invoke the Lambda function.
resource "aws_lambda_permission" "cwl_invoke" {
  count         = var.deploy_lambda_transformer && var.deploy_cloudwatch_logs ? 1 : 0
  statement_id  = "AllowExecutionFromCloudWatchLogs"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cw_to_kinesis[0].function_name
  principal     = "logs.${data.aws_region.current.name}.amazonaws.com"
  source_arn    = "${aws_cloudwatch_log_group.app_logs[0].arn}:*"
}

###############################
// CloudWatch Logs Subscription Filter
// ---------------------------------------------------------------------
// Wires the log group to the Lambda transformer. The filter pattern
// defaults to "" (all events); narrow it via
// var.cloudwatch_subscription_filter_pattern if needed.
###############################
resource "aws_cloudwatch_log_subscription_filter" "to_lambda" {
  count = var.deploy_cloudwatch_logs && var.deploy_lambda_transformer ? 1 : 0

  name            = "cw-to-lambda-transformer"
  log_group_name  = aws_cloudwatch_log_group.app_logs[0].name
  filter_pattern  = var.cloudwatch_subscription_filter_pattern
  destination_arn = aws_lambda_function.cw_to_kinesis[0].arn

  depends_on = [aws_lambda_permission.cwl_invoke]
}

###############################
// IAM Resources for Kinesis ClickPipe
// ---------------------------------------------------------------------
// ClickHouse Cloud's Kinesis ClickPipe assumes a customer-owned IAM
// role to read records from the Kinesis stream. Trust is established
// against the IAM role ARN that ClickHouse exposes on the service
// resource (clickhouse_service.iam_role), exactly mirroring the S3
// ClickPipe pattern in main.tf.
//
// Permission policy is the minimum required set documented at
//   https://clickhouse.com/docs/integrations/clickpipes/kinesis/auth
###############################
resource "aws_iam_policy" "clickhouse_kinesis_access" {
  count       = var.deploy_clickhouse && var.deploy_cloudwatch_clickpipe ? 1 : 0
  name        = "ClickHouseKinesisAccessPolicy"
  description = "Policy allowing the Kinesis ClickPipe to read from the demo Kinesis Data Stream"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords",
          "kinesis:ListShards",
          "kinesis:RegisterStreamConsumer",
          "kinesis:DeregisterStreamConsumer",
          "kinesis:ListStreamConsumers",
        ],
        Resource = aws_kinesis_stream.log_stream[0].arn
      },
      {
        Effect = "Allow",
        Action = [
          "kinesis:SubscribeToShard",
          "kinesis:DescribeStreamConsumer",
        ],
        Resource = "${aws_kinesis_stream.log_stream[0].arn}/*"
      },
      {
        Effect   = "Allow",
        Action   = ["kinesis:ListStreams"],
        Resource = "*"
      },
    ]
  })
}

// Role that the Kinesis ClickPipe assumes to read records. The trust
// policy is written inline using clickhouse_service.service[0].iam_role;
// Terraform's dependency graph guarantees the ClickHouse service is
// provisioned before this role is created, so the ARN is always known
// at create time.
resource "aws_iam_role" "clickhouse_kinesis_role" {
  count = var.deploy_clickhouse && var.deploy_cloudwatch_clickpipe ? 1 : 0
  name  = var.clickhouse_kinesis_iam_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { AWS = clickhouse_service.service[0].iam_role },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "clickhouse_kinesis_access" {
  count      = length(aws_iam_role.clickhouse_kinesis_role) > 0 ? 1 : 0
  role       = aws_iam_role.clickhouse_kinesis_role[0].name
  policy_arn = aws_iam_policy.clickhouse_kinesis_access[0].arn
}

// IAM is eventually consistent; wait before the Kinesis ClickPipe
// attempts to assume the role. 300s matches the S3 wait in main.tf.
resource "time_sleep" "wait_for_kinesis_iam_propagation" {
  count           = var.deploy_clickhouse && var.deploy_cloudwatch_clickpipe ? 1 : 0
  depends_on      = [aws_iam_role_policy_attachment.clickhouse_kinesis_access]
  create_duration = "300s"
}

###############################
// Kinesis ClickPipe Resource (streaming CloudWatch Logs pipeline)
// ---------------------------------------------------------------------
// Real-time ingestion from the Kinesis stream into the cloudwatch_logs
// table. Records on the stream are clean JSONEachRow events produced
// by the Lambda transformer, so no further decoding is required.
###############################
resource "clickhouse_clickpipe" "cloudwatch_logs" {
  count = var.deploy_clickhouse && var.deploy_cloudwatch_clickpipe ? 1 : 0
  name  = "CloudWatch Logs Streaming Pipeline"

  service_id = clickhouse_service.service[0].id

  source = {
    kinesis = {
      format               = var.cloudwatch_clickpipe_format
      stream_name          = aws_kinesis_stream.log_stream[0].name
      region               = var.aws_region
      iterator_type        = var.cloudwatch_clickpipe_iterator_type
      use_enhanced_fan_out = var.cloudwatch_clickpipe_use_enhanced_fan_out
      authentication       = "IAM_ROLE"
      iam_role             = aws_iam_role.clickhouse_kinesis_role[0].arn
    }
  }

  destination = {
    table         = var.cloudwatch_clickpipe_table_name
    managed_table = true

    table_definition = {
      engine = {
        type = "MergeTree"
      }
    }

    columns = var.cloudwatch_clickpipe_columns
  }

  depends_on = [
    time_sleep.wait_for_kinesis_iam_propagation,
    aws_cloudwatch_log_subscription_filter.to_lambda,
  ]
}
