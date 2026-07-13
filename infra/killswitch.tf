# ── Tiered auto-pause kill switch + real-time tripwires (Phase 3) ─────────────
# The breaker Lambda writes a degradation TIER onto a DynamoDB flag item:
#   • A real-time CloudWatch alarm (Bedrock/Maxi/API/concurrency spike) -> ALARM
#     publishes here -> breaker sets level="degraded" (shed the heaviest AI, run
#     Maxi cheap+short). When the alarm CLEARS, its OK action publishes here too
#     and the breaker AUTO-RESUMES (plus a 30-min read-side backstop) — no page.
#   • The monthly budget LIMIT (var.monthly_budget_limit_usd) -> level="paused"
#     (hard cap): kill non-essential AI; human resume only.
# The API Lambda reads the tier (fail-open, cached); auth, feed/posts, and data
# collection keep serving at every tier.

# ── Flag + counters store ─────────────────────────────────────────────────────
# Items: { key:"feature-flags", level, paused (back-compat), reason, since,
# autoResumeAt }; the Maxi monthly budget (key maxi-budget#YYYY-MM); and per-user
# rate-limit counters (key maxi-rate#<day>#<principal>) that self-purge via the
# expiresAt TTL below.
resource "aws_dynamodb_table" "config" {
  name         = "${local.prefix}-config"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "key"

  attribute {
    name = "key"
    type = "S"
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }
}

# ── Kill-switch trigger topic (the $1,000 budget + CloudWatch alarms publish) ──
resource "aws_sns_topic" "cost_killswitch" {
  name = "${local.prefix}-cost-killswitch"
}

data "aws_iam_policy_document" "cost_killswitch_publish" {
  statement {
    sid       = "AllowBudgetsPublish"
    effect    = "Allow"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.cost_killswitch.arn]
    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:budgets::${data.aws_caller_identity.current.account_id}:budget/*"]
    }
  }

  statement {
    sid       = "AllowCloudWatchAlarmsPublish"
    effect    = "Allow"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.cost_killswitch.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "cost_killswitch" {
  arn    = aws_sns_topic.cost_killswitch.arn
  policy = data.aws_iam_policy_document.cost_killswitch_publish.json
}

# ── Breaker Lambda (reuses the API source bundle; handler = breaker.handler) ───
resource "aws_cloudwatch_log_group" "breaker" {
  name              = "/aws/lambda/${local.prefix}-breaker"
  retention_in_days = 14
}

# Dedicated least-privilege role (NOT the shared API role — the API Lambda must
# not be able to write the flag; only the breaker can).
resource "aws_iam_role" "breaker" {
  name               = "${local.prefix}-breaker"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "breaker_logs" {
  role       = aws_iam_role.breaker.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "breaker_access" {
  statement {
    sid       = "ConfigFlagRW"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.config.arn]
  }
  statement {
    sid       = "PublishAlerts"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.cost_alerts.arn]
  }
}

resource "aws_iam_role_policy" "breaker_access" {
  name   = "${local.prefix}-breaker-access"
  role   = aws_iam_role.breaker.id
  policy = data.aws_iam_policy_document.breaker_access.json
}

resource "aws_lambda_function" "breaker" {
  function_name    = "${local.prefix}-breaker"
  role             = aws_iam_role.breaker.arn
  runtime          = "nodejs20.x"
  handler          = "breaker.handler"
  filename         = data.archive_file.api.output_path
  source_code_hash = data.archive_file.api.output_base64sha256
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      CONFIG_TABLE          = aws_dynamodb_table.config.name
      COST_ALERTS_TOPIC_ARN = aws_sns_topic.cost_alerts.arn
      RESUME_HINT           = "aws lambda invoke --function-name ${local.prefix}-breaker --payload '{\"action\":\"resume\"}' --cli-binary-format raw-in-base64-out /dev/stdout"
      # Backstop window for an alarm-induced "degraded" tier (the alarm clearing
      # resumes sooner). The API handler honors the same value on read.
      DEGRADE_AUTORESUME_MIN = "30"
    }
  }

  depends_on = [aws_cloudwatch_log_group.breaker]
}

# Wire the kill-switch topic -> breaker Lambda.
resource "aws_sns_topic_subscription" "killswitch_to_breaker" {
  topic_arn = aws_sns_topic.cost_killswitch.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.breaker.arn
}

resource "aws_lambda_permission" "killswitch_invoke_breaker" {
  statement_id  = "AllowSNSInvokeBreaker"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.breaker.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.cost_killswitch.arn
}

# API Lambda config access: GET the kill-switch flag + GET/UPDATE Maxi's monthly
# Bedrock budget counter (key maxi-budget#YYYY-MM). The handler never writes the
# "paused" flag in code (only the breaker does); both items share the config table.
data "aws_iam_policy_document" "api_config_read" {
  statement {
    sid       = "ConfigReadWrite"
    actions   = ["dynamodb:GetItem", "dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.config.arn]
  }
}

resource "aws_iam_role_policy" "api_config_read" {
  name   = "${local.prefix}-api-config-read"
  role   = aws_iam_role.api_lambda.id
  policy = data.aws_iam_policy_document.api_config_read.json
}

# ── Real-time tripwires: trip the breaker in MINUTES (billing budgets lag) ─────
# Each alarm's ALARM action publishes to the kill-switch topic -> breaker sets
# "degraded"; its OK action publishes there too -> breaker auto-resumes. (These
# real-time spikes DEGRADE, not hard-pause — only the monthly budget hard-pauses.)
resource "aws_cloudwatch_metric_alarm" "bedrock_invocations" {
  alarm_name          = "${local.prefix}-bedrock-invocations-spike"
  alarm_description   = "Bedrock (Titan) invocations spiked in 5 min — possible runaway AI cost. Trips the cost kill switch."
  namespace           = "AWS/Bedrock"
  metric_name         = "Invocations"
  dimensions          = { ModelId = local.bedrock_embed_model_id }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.alarm_bedrock_invocations_5min
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.cost_killswitch.arn]
  ok_actions          = [aws_sns_topic.cost_killswitch.arn]
}

# ── Maxi model-router tripwires (POST /maxi) ──────────────────────────────────
# Mirror the Titan alarm above for BOTH Maxi router models (Nova base + Haiku
# shopping). CloudWatch's AWS/Bedrock "Invocations" metric is dimensioned by
# ModelId; with a cross-region inference profile it's ambiguous whether AWS emits
# the PROFILE id (us.amazon.nova-lite-v1:0) or the underlying FOUNDATION model id
# (amazon.nova-lite-v1:0), and it can vary by account/region. So we create an
# alarm for BOTH forms of each model — only the dimension AWS actually emits
# carries data; the rest stay dormant (treat_missing_data = notBreaching).
# Confirm the real dimension in the CloudWatch console after the first live Maxi
# call, then prune the dormant ones if you like. All auto-tag + join the resource
# group via provider default_tags (providers.tf / resource_group.tf).
locals {
  maxi_alarm_model_ids = toset(concat(
    local.maxi_model_ids,
    [for m in local.maxi_model_ids : replace(m, "us.", "")]
  ))
}

resource "aws_cloudwatch_metric_alarm" "maxi_invocations" {
  for_each = local.maxi_alarm_model_ids

  alarm_name          = "${local.prefix}-maxi-invocations-spike-${replace(replace(each.value, ":", "-"), ".", "-")}"
  alarm_description   = "Maxi (Bedrock Converse) invocations spiked in 5 min for ModelId '${each.value}' — possible runaway agent cost. Trips the cost kill switch. With cross-region inference, only the ModelId AWS actually emits carries data."
  namespace           = "AWS/Bedrock"
  metric_name         = "Invocations"
  dimensions          = { ModelId = each.value }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.alarm_maxi_invocations_5min
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.cost_killswitch.arn]
  ok_actions          = [aws_sns_topic.cost_killswitch.arn]
}

resource "aws_cloudwatch_metric_alarm" "api_request_spike" {
  alarm_name          = "${local.prefix}-api-request-spike"
  alarm_description   = "API Gateway request volume spiked in 5 min — trips the cost kill switch."
  namespace           = "AWS/ApiGatewayV2"
  metric_name         = "Count"
  dimensions          = { ApiId = aws_apigatewayv2_api.http.id }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.alarm_api_requests_5min
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.cost_killswitch.arn]
  ok_actions          = [aws_sns_topic.cost_killswitch.arn]
}

# ── API Lambda resilience (notify-only) ───────────────────────────────────────
# The mobile app + admin/ingest still hit the api Lambda directly (not just App
# Runner), so its health IS a meaningful signal. These NOTIFY the cost-alerts
# topic (they don't trip the kill switch — the API request-spike above handles
# the cost tripwire). Throttles firing means the reserved-concurrency cap
# (var.api_reserved_concurrency) is being hit — a runaway or a real traffic
# surge — exactly the Jun 2026 flood signature that had no direct Lambda alarm.
resource "aws_cloudwatch_metric_alarm" "api_lambda_throttles" {
  alarm_name          = "${local.prefix}-api-lambda-throttles"
  alarm_description   = "API Lambda is being throttled (hitting the reserved-concurrency cap) — runaway or traffic surge."
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  dimensions          = { FunctionName = aws_lambda_function.api.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 100
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.cost_alerts.arn]
  ok_actions          = [aws_sns_topic.cost_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "api_lambda_errors" {
  alarm_name          = "${local.prefix}-api-lambda-errors"
  alarm_description   = "API Lambda error count elevated (>50 in 5 min) — app faults or a bad deploy."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.api.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 50
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.cost_alerts.arn]
  ok_actions          = [aws_sns_topic.cost_alerts.arn]
}

# Concurrency tripwire — watches the App Runner service (the live API) instead of
# the legacy Lambda. AWS/AppRunner "Concurrency" = concurrent requests in flight;
# a sustained spike DEGRADES non-essential AI then auto-resumes (dims defined in
# apprunner.tf). The legacy api Lambda is bypassed, so its concurrency is no
# longer a meaningful cost signal.
resource "aws_cloudwatch_metric_alarm" "apprunner_concurrency" {
  alarm_name          = "${local.prefix}-apprunner-concurrency-high"
  alarm_description   = "App Runner API concurrent requests high — real-time cost tripwire: degrades non-essential AI (Maxi cheap+short; pause visual search / vector recs / pins), then AUTO-RESUMES when it clears."
  namespace           = "AWS/AppRunner"
  metric_name         = "Concurrency"
  dimensions          = local.apprunner_dims
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = var.alarm_apprunner_concurrency
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.cost_killswitch.arn]
  ok_actions          = [aws_sns_topic.cost_killswitch.arn]
}
