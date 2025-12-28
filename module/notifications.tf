# =============================================================================
# Pipeline Failure Notifications
# =============================================================================

# -----------------------------------------------------------------------------
# SNS Topic for Pipeline Notifications
# -----------------------------------------------------------------------------

resource "aws_sns_topic" "pipeline_notifications" {
  count = var.enable_cicd ? 1 : 0
  name  = "${var.project_name}-pipeline-notifications"

  tags = {
    Name = "${var.project_name}-pipeline-notifications"
  }
}

resource "aws_sns_topic_subscription" "pipeline_email" {
  count     = var.enable_cicd && var.pipeline_notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.pipeline_notifications[0].arn
  protocol  = "email"
  endpoint  = var.pipeline_notification_email
}

# -----------------------------------------------------------------------------
# CloudWatch Event Rule for Pipeline Failures
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "pipeline_failure" {
  count       = var.enable_cicd ? 1 : 0
  name        = "${var.project_name}-pipeline-failure"
  description = "Trigger when CodePipeline fails"

  event_pattern = jsonencode({
    source      = ["aws.codepipeline"]
    detail-type = ["CodePipeline Pipeline Execution State Change"]
    detail = {
      state    = ["FAILED"]
      pipeline = [aws_codepipeline.main[0].name]
    }
  })

  tags = {
    Name = "${var.project_name}-pipeline-failure-rule"
  }
}

resource "aws_cloudwatch_event_target" "pipeline_failure_sns" {
  count     = var.enable_cicd ? 1 : 0
  rule      = aws_cloudwatch_event_rule.pipeline_failure[0].name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.pipeline_notifications[0].arn

  input_transformer {
    input_paths = {
      pipeline  = "$.detail.pipeline"
      state     = "$.detail.state"
      execution = "$.detail.execution-id"
      time      = "$.time"
    }
    input_template = "\"Pipeline '<pipeline>' has <state> at <time>. Execution ID: <execution>\""
  }
}

# -----------------------------------------------------------------------------
# SNS Topic Policy
# -----------------------------------------------------------------------------

resource "aws_sns_topic_policy" "pipeline_notifications" {
  count = var.enable_cicd ? 1 : 0
  arn   = aws_sns_topic.pipeline_notifications[0].arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.pipeline_notifications[0].arn
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "sns_topic_arn" {
  description = "ARN of the SNS topic for pipeline notifications"
  value       = var.enable_cicd ? aws_sns_topic.pipeline_notifications[0].arn : null
}

output "pipeline_notification_email" {
  description = "Email address for pipeline notifications"
  value       = var.pipeline_notification_email
  sensitive   = true
}
