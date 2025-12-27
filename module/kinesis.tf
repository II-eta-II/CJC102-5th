# IAM Role for Kinesis Data Firehose
resource "aws_iam_role" "firehose_waf" {
  provider = aws.us_east_1
  name     = "${var.project_name}-firehose-waf-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-firehose-waf-role"
  }
}

# IAM Policy for Kinesis Data Firehose to write to S3
resource "aws_iam_role_policy" "firehose_waf_s3" {
  provider = aws.us_east_1
  name     = "${var.project_name}-firehose-waf-s3-policy"
  role     = aws_iam_role.firehose_waf.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.waf_logs.arn,
          "${aws_s3_bucket.waf_logs.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:log-group:/aws/kinesis_firehose/${var.project_name}-waf:*"
        ]
      }
    ]
  })
}

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {
  provider = aws.us_east_1
}

# CloudWatch Log Group for Kinesis Data Firehose
resource "aws_cloudwatch_log_group" "firehose_waf" {
  provider          = aws.us_east_1
  name              = "/aws/kinesis_firehose/${var.project_name}-waf"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-firehose-waf-logs"
  }
}

# Kinesis Data Firehose Delivery Stream for WAF Logs
# 注意：AWS WAF 要求 Firehose Stream 名稱必須以 aws-waf-logs- 開頭
resource "aws_kinesis_firehose_delivery_stream" "waf_logs" {
  provider    = aws.us_east_1
  name        = "aws-waf-logs-${var.project_name}-stream"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.firehose_waf.arn
    bucket_arn          = aws_s3_bucket.waf_logs.arn
    prefix              = "waf-logs/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"
    error_output_prefix = "waf-logs-errors/"

    buffering_size     = 5
    buffering_interval = 60

    compression_format = "GZIP"

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose_waf.name
      log_stream_name = "${var.project_name}-waf-firehose-stream"
    }
  }

  tags = {
    Name = "aws-waf-logs-${var.project_name}-stream"
  }
}

