"""CloudWatch Logs subscription filter -> Kinesis Data Stream transformer.

CloudWatch Logs subscription filters always deliver gzip-compressed
JSON envelopes that wrap N individual log events. ClickPipe's Kinesis
source expects clean JSONEachRow records, so this Lambda:

  1. Base64-decodes and gunzips the subscription payload.
  2. Parses the envelope and skips CONTROL_MESSAGE pings.
  3. Emits one Kinesis record per logEvent with a flat schema that
     matches the cloudwatch_clickpipe_columns variable in variables.tf.

Records are PutRecord'd in batches of up to 500 (the Kinesis API
limit). The function is invoked synchronously by CloudWatch Logs;
unhandled exceptions are surfaced to CW Logs subscription delivery
retries.
"""

import base64
import gzip
import json
import os

import boto3

_kinesis = boto3.client("kinesis")
_STREAM_NAME = os.environ["DESTINATION_STREAM_NAME"]
_KINESIS_PUT_BATCH = 500


def lambda_handler(event, _context):
    payload = event["awslogs"]["data"]
    envelope = json.loads(gzip.decompress(base64.b64decode(payload)))

    if envelope.get("messageType") != "DATA_MESSAGE":
        return {"statusCode": 200, "skipped": envelope.get("messageType")}

    log_group = envelope["logGroup"]
    log_stream = envelope["logStream"]
    owner = envelope["owner"]

    records = [
        {
            "Data": (
                json.dumps(
                    {
                        "log_group": log_group,
                        "log_stream": log_stream,
                        "owner": owner,
                        "timestamp": log_event["timestamp"],
                        "id": log_event["id"],
                        "message": log_event["message"],
                    },
                    separators=(",", ":"),
                ).encode("utf-8")
                + b"\n"
            ),
            "PartitionKey": log_event["id"],
        }
        for log_event in envelope["logEvents"]
    ]

    forwarded = 0
    for start in range(0, len(records), _KINESIS_PUT_BATCH):
        chunk = records[start : start + _KINESIS_PUT_BATCH]
        response = _kinesis.put_records(StreamName=_STREAM_NAME, Records=chunk)
        forwarded += len(chunk) - response.get("FailedRecordCount", 0)

    return {"statusCode": 200, "records_forwarded": forwarded, "received": len(records)}
