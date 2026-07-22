# ── Event reminders ───────────────────────────────────────────────────────────
# A daily job scans the users table for upcoming logged events (birthdays,
# anniversaries, …) and publishes reminders to an SNS topic. Subscribe an
# endpoint to receive them, e.g.:
#   aws sns subscribe --topic-arn <reminders_topic_arn> \
#     --protocol email --notification-endpoint you@example.com
#
# Reuses the API Lambda's source bundle (reminders.mjs lives in src/) and IAM
# role (already has DynamoDB scan on users + logs); we just add SNS:Publish.

resource "aws_sns_topic" "reminders" {
  name = "${local.prefix}-reminders"
}

resource "aws_cloudwatch_log_group" "reminders" {
  name              = "/aws/lambda/${local.prefix}-reminders"
  retention_in_days = 14
}

resource "aws_lambda_function" "reminders" {
  function_name    = "${local.prefix}-reminders"
  role             = aws_iam_role.api_lambda.arn
  runtime          = "nodejs20.x"
  handler          = "reminders.handler"
  filename         = data.archive_file.api.output_path
  source_code_hash = data.archive_file.api.output_base64sha256
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      USERS_TABLE         = aws_dynamodb_table.users.name
      REMINDERS_TOPIC_ARN = aws_sns_topic.reminders.arn
      # APNs push for due events (push.mjs). The ARN stays empty until the
      # APNs key is supplied (var.apns_private_key) — the sender no-ops.
      DEVICES_TABLE = aws_dynamodb_table.devices.name
      # join("") yields "" when the platform app is absent (count = 0); coalesce
      # can't be used here because it rejects empty strings and would error.
      SNS_PLATFORM_APP_ARN = join("", aws_sns_platform_application.ios_push[*].arn)
    }
  }

  depends_on = [aws_cloudwatch_log_group.reminders]
}

# Fire once a day at 09:00 UTC. Adjust the cron as needed.
resource "aws_cloudwatch_event_rule" "reminders_daily" {
  name                = "${local.prefix}-reminders-daily"
  description         = "Trigger Giftmaxxing event reminders once a day"
  schedule_expression = "cron(0 9 * * ? *)"
}

resource "aws_cloudwatch_event_target" "reminders_daily" {
  rule      = aws_cloudwatch_event_rule.reminders_daily.name
  target_id = "reminders-lambda"
  arn       = aws_lambda_function.reminders.arn
}

resource "aws_lambda_permission" "reminders_events" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.reminders.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.reminders_daily.arn
}

# Let the shared Lambda role publish reminder notifications.
data "aws_iam_policy_document" "sns_publish" {
  statement {
    sid       = "PublishReminders"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.reminders.arn]
  }
}

resource "aws_iam_role_policy" "sns_publish" {
  name   = "${local.prefix}-sns-publish"
  role   = aws_iam_role.api_lambda.id
  policy = data.aws_iam_policy_document.sns_publish.json
}
