# ── App Runner: the API, off the Lambda concurrency cap ───────────────────────
# Runs the SAME handler.mjs (via server.mjs) as an always-on, autoscaling
# container instead of a per-invocation Lambda. One instance multiplexes ~100
# concurrent I/O-bound requests on the Node event loop; App Runner adds instances
# under load. DynamoDB / Bedrock / S3 Vectors are unchanged; the breaker +
# reminders stay on Lambda (event-driven, not user-facing). The api Lambda + API
# Gateway are left in place for a safe, reversible cutover (switch the frontend's
# NEXT_PUBLIC_API_URL to the App Runner URL, then decommission them).

# ── IAM: instance role (the running app's permissions) ────────────────────────
# Mirrors the api Lambda role: DynamoDB, S3 Vectors, Bedrock, and the config
# table (kill-switch flag + Maxi budget/rate counters). Reuses the exact same
# policy documents defined in iam.tf / lambda.tf so permissions never drift.
data "aws_iam_policy_document" "apprunner_instance_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["tasks.apprunner.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "apprunner_instance" {
  name               = "${local.prefix}-apprunner-instance"
  assume_role_policy = data.aws_iam_policy_document.apprunner_instance_assume.json
}

resource "aws_iam_role_policy" "apprunner_ddb" {
  name   = "${local.prefix}-apprunner-ddb"
  role   = aws_iam_role.apprunner_instance.id
  policy = data.aws_iam_policy_document.ddb_access.json
}

resource "aws_iam_role_policy" "apprunner_s3vectors" {
  name   = "${local.prefix}-apprunner-s3vectors"
  role   = aws_iam_role.apprunner_instance.id
  policy = data.aws_iam_policy_document.s3vectors_access.json
}

resource "aws_iam_role_policy" "apprunner_bedrock" {
  name   = "${local.prefix}-apprunner-bedrock"
  role   = aws_iam_role.apprunner_instance.id
  policy = data.aws_iam_policy_document.bedrock_access.json
}

resource "aws_iam_role_policy" "apprunner_config" {
  name   = "${local.prefix}-apprunner-config"
  role   = aws_iam_role.apprunner_instance.id
  policy = data.aws_iam_policy_document.api_config_read.json
}

resource "aws_iam_role_policy" "apprunner_login_email" {
  name   = "${local.prefix}-apprunner-login-email"
  role   = aws_iam_role.apprunner_instance.id
  policy = data.aws_iam_policy_document.login_email.json
}

resource "aws_iam_role_policy" "apprunner_sagemaker_invoke" {
  name   = "${local.prefix}-apprunner-sagemaker-invoke"
  role   = aws_iam_role.apprunner_instance.id
  policy = data.aws_iam_policy_document.sagemaker_invoke.json
}

resource "aws_iam_role_policy" "apprunner_ugc_media" {
  name   = "${local.prefix}-apprunner-ugc-media"
  role   = aws_iam_role.apprunner_instance.id
  policy = data.aws_iam_policy_document.ugc_api_media.json
}

# ── IAM: access role (App Runner pulls the image from private ECR) ─────────────
data "aws_iam_policy_document" "apprunner_access_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["build.apprunner.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "apprunner_access" {
  name               = "${local.prefix}-apprunner-ecr-access"
  assume_role_policy = data.aws_iam_policy_document.apprunner_access_assume.json
}

resource "aws_iam_role_policy_attachment" "apprunner_ecr" {
  role       = aws_iam_role.apprunner_access.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess"
}

# ── Autoscaling: per-instance concurrency + instance bounds ───────────────────
resource "aws_apprunner_auto_scaling_configuration_version" "api" {
  auto_scaling_configuration_name = "${local.prefix}-api"

  max_concurrency = 100 # requests per instance before scaling out
  min_size        = 1   # always one warm instance (no cold start)
  max_size        = 5   # ceiling (100 * 5 = 500 concurrent requests)

  lifecycle {
    create_before_destroy = true
  }
}

# ── The service ───────────────────────────────────────────────────────────────
resource "aws_apprunner_service" "api" {
  service_name = "${local.prefix}-api"

  source_configuration {
    auto_deployments_enabled = false # we deploy explicitly (push + start-deployment)

    image_repository {
      image_identifier      = "${aws_ecr_repository.api.repository_url}:latest"
      image_repository_type = "ECR"

      image_configuration {
        port = "8080"

        # Same environment as the api Lambda (lambda.tf) so behavior is identical.
        runtime_environment_variables = merge({
          PORT               = "8080"
          USERS_TABLE        = aws_dynamodb_table.users.name
          POSTS_TABLE        = aws_dynamodb_table.posts.name
          UGC_REPORTS_TABLE  = aws_dynamodb_table.ugc_reports.name
          MEDIA_BUCKET       = aws_s3_bucket.media.id
          INTERACTIONS_TABLE = aws_dynamodb_table.interactions.name
          KNOWLEDGE_TABLE    = aws_dynamodb_table.knowledge.name
          CONNECTIONS_TABLE  = aws_dynamodb_table.connections.name
          CHALLENGES_TABLE   = aws_dynamodb_table.challenges.name
          POOLS_TABLE        = aws_dynamodb_table.pools.name
          FRIENDS_TABLE      = aws_dynamodb_table.friends.name
          EVENTS_TABLE       = aws_dynamodb_table.events.name
          GRAPH_TABLE        = aws_dynamodb_table.graph.name
          CONFIG_TABLE       = aws_dynamodb_table.config.name
          ANALYTICS_TABLE    = aws_dynamodb_table.analytics.name
          DEVICES_TABLE      = aws_dynamodb_table.devices.name
          # Without this, pushConfigured() is false and EVERY push silently
          # no-ops. lambda.tf always had it; App Runner didn't — and App Runner
          # is what the app actually reaches through CloudFront, so no push has
          # ever been delivered (0 SNS endpoints against 9 registered tokens).
          SNS_PLATFORM_APP_ARN = join("", aws_sns_platform_application.ios_push[*].arn)

          AUTH_ENFORCE       = var.auth_enforce ? "1" : "0"
          ADMIN_API_SECRET   = var.admin_api_secret
          CLERK_ISSUER       = var.clerk_issuer
          SESSION_JWT_SECRET = var.session_jwt_secret
          # iOS-app identities (mirrors lambda.tf — see handler.mjs verifiers).
          COGNITO_ISSUER         = "https://${aws_cognito_user_pool.mobile.endpoint}"
          COGNITO_CLIENT_ID      = aws_cognito_user_pool_client.ios.id
          GOOGLE_OAUTH_CLIENT_ID = var.google_oauth_client_id

          VECTOR_BUCKET          = "${local.prefix}-vectors"
          VECTOR_INDEX           = "pins"
          BEDROCK_EMBED_MODEL_ID = "amazon.titan-embed-image-v1"
          VECTOR_DIM             = "1024"
          # MTL value-model re-rank (CLOUD.md §16) — same contract as lambda.tf.
          MTL_ENDPOINT = var.mtl_endpoint

          MAXI_BASE_MODEL_ID     = var.maxi_base_model_id
          MAXI_SHOPPING_MODEL_ID = var.maxi_shopping_model_id
          MAXI_MODEL_ID          = var.maxi_model_id

          MAXI_MAX_TOKENS               = tostring(var.maxi_max_tokens)
          MAXI_INTERACTION_TOKEN_BUDGET = tostring(var.maxi_interaction_token_budget)
          MAXI_MAX_STEPS                = tostring(var.maxi_max_steps)
          MAXI_MONTHLY_BUDGET_USD       = tostring(var.maxi_monthly_budget_usd)

          MAXI_BASE_PRICE_IN_PER_1M      = tostring(var.maxi_base_price_in_per_1m)
          MAXI_BASE_PRICE_OUT_PER_1M     = tostring(var.maxi_base_price_out_per_1m)
          MAXI_SHOPPING_PRICE_IN_PER_1M  = tostring(var.maxi_price_in_per_1m)
          MAXI_SHOPPING_PRICE_OUT_PER_1M = tostring(var.maxi_price_out_per_1m)
          MAXI_PRICE_IN_PER_1M           = tostring(var.maxi_price_in_per_1m)
          MAXI_PRICE_OUT_PER_1M          = tostring(var.maxi_price_out_per_1m)

          MAXI_DAILY_LIMIT = tostring(var.maxi_daily_limit)
          FEED_SHARDS      = tostring(var.feed_shards)
          },
          try(trimspace(var.login_reset_url), "") == "" ? {} : { LOGIN_RESET_URL = var.login_reset_url },
          try(trimspace(var.login_email_from), "") == "" ? {} : { LOGIN_EMAIL_FROM = var.login_email_from },
        )
      }
    }

    authentication_configuration {
      access_role_arn = aws_iam_role.apprunner_access.arn
    }
  }

  instance_configuration {
    # Downsized from 1 vCPU / 2 GB (PR #34) for cost. NOTE: production mobile +
    # web BOTH reach this service via CloudFront (d21osnvwewgoao.cloudfront.net)
    # — NOT the legacy API Gateway → Lambda path. The older "website only /
    # mobile uses Lambda" claim was wrong; see
    # docs/api-concurrency-investigation-2026-07-13.md. Size/concurrency changes
    # need a team decision (do not silently re-tune). Observed util after the
    # downsize is still low avg CPU/mem, but RequestLatency tails can hit 1–2s.
    # min_size stays 1 (App Runner's floor) so there's still no cold start.
    cpu               = "256" # 0.25 vCPU
    memory            = "512" # 0.5 GB
    instance_role_arn = aws_iam_role.apprunner_instance.arn
  }

  health_check_configuration {
    protocol            = "HTTP"
    path                = "/healthz"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 1
    unhealthy_threshold = 5
  }

  auto_scaling_configuration_arn = aws_apprunner_auto_scaling_configuration_version.api.arn

  depends_on = [
    aws_iam_role_policy.apprunner_ddb,
    aws_iam_role_policy.apprunner_s3vectors,
    aws_iam_role_policy.apprunner_bedrock,
    aws_iam_role_policy.apprunner_config,
    aws_iam_role_policy.apprunner_ugc_media,
    aws_iam_role_policy_attachment.apprunner_ecr,
  ]
}

# ── CloudWatch alarms (notify the existing cost-alerts SNS topic) ──────────────
# Operational health of the App Runner service. These NOTIFY only — they do NOT
# trip the cost kill switch (that is reserved for AI cost spikes).
locals {
  apprunner_dims = {
    ServiceName = aws_apprunner_service.api.service_name
    ServiceID   = aws_apprunner_service.api.service_id
  }
}

resource "aws_cloudwatch_metric_alarm" "apprunner_5xx" {
  alarm_name          = "${local.prefix}-apprunner-5xx"
  alarm_description   = "App Runner API returning 5xx responses (app errors / unhealthy instances)."
  namespace           = "AWS/AppRunner"
  metric_name         = "5xxStatusResponses"
  dimensions          = local.apprunner_dims
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 25
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.cost_alerts.arn]
  ok_actions          = [aws_sns_topic.cost_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "apprunner_latency" {
  alarm_name          = "${local.prefix}-apprunner-latency"
  alarm_description   = "App Runner API p99 request latency is high (>3s)."
  namespace           = "AWS/AppRunner"
  metric_name         = "RequestLatency"
  dimensions          = local.apprunner_dims
  extended_statistic  = "p99"
  period              = 300
  evaluation_periods  = 3
  threshold           = 3000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.cost_alerts.arn]
  ok_actions          = [aws_sns_topic.cost_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "apprunner_cpu" {
  alarm_name          = "${local.prefix}-apprunner-cpu-high"
  alarm_description   = "App Runner API CPU utilization sustained high (>80%)."
  namespace           = "AWS/AppRunner"
  metric_name         = "CPUUtilization"
  dimensions          = local.apprunner_dims
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.cost_alerts.arn]
  ok_actions          = [aws_sns_topic.cost_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "apprunner_memory" {
  alarm_name          = "${local.prefix}-apprunner-memory-high"
  alarm_description   = "App Runner API memory utilization sustained high (>85%)."
  namespace           = "AWS/AppRunner"
  metric_name         = "MemoryUtilization"
  dimensions          = local.apprunner_dims
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.cost_alerts.arn]
  ok_actions          = [aws_sns_topic.cost_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "apprunner_at_max" {
  alarm_name          = "${local.prefix}-apprunner-at-max-instances"
  alarm_description   = "App Runner API is running at its max instance ceiling — consider raising max_size."
  namespace           = "AWS/AppRunner"
  metric_name         = "ActiveInstances"
  dimensions          = local.apprunner_dims
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 3
  threshold           = aws_apprunner_auto_scaling_configuration_version.api.max_size
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.cost_alerts.arn]
  ok_actions          = [aws_sns_topic.cost_alerts.arn]
}

output "apprunner_api_url" {
  description = "App Runner API endpoint — set this as NEXT_PUBLIC_API_URL to cut the frontend over."
  value       = "https://${aws_apprunner_service.api.service_url}"
}
