# Zip the handler source. DynamoDB clients come from the nodejs20.x runtime SDK;
# @aws-sdk/client-s3vectors is NOT in the runtime, so it's npm-installed into
# src/node_modules and bundled here (run `npm install` in src/ before apply).
data "archive_file" "api" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/build/api.zip"
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/lambda/${local.prefix}-api"
  retention_in_days = 14
}

resource "aws_lambda_function" "api" {
  function_name    = "${local.prefix}-api"
  role             = aws_iam_role.api_lambda.arn
  runtime          = "nodejs20.x"
  handler          = "handler.handler"
  filename         = data.archive_file.api.output_path
  source_code_hash = data.archive_file.api.output_base64sha256
  timeout          = 10
  memory_size      = 256

  # Baseline autoscale ceiling so a traffic/runaway spike can't balloon Lambda
  # (and thus DynamoDB) cost. The $1,000 kill switch pauses the expensive AI
  # routes on top of this (see killswitch.tf). -1 (via var) = uncapped.
  reserved_concurrent_executions = var.api_reserved_concurrency

  environment {
    variables = {
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
      # APNs push: device registration (mobile-routes) + sends (push.mjs). The
      # platform-app ARN stays "" until var.apns_private_key is supplied.
      DEVICES_TABLE = aws_dynamodb_table.devices.name
      # join("") yields "" when the platform app is absent (count = 0); coalesce
      # can't be used here because it rejects empty strings and would error.
      SNS_PLATFORM_APP_ARN = join("", aws_sns_platform_application.ios_push[*].arn)
      # API auth (in-handler Clerk-JWT / x-admin-token gate; see handler.mjs).
      # AUTH_ENFORCE ships false so the code is dark until flipped on; flip back
      # to false for an instant rollback. ADMIN_API_SECRET is the admin/ingest
      # "password"; CLERK_ISSUER verifies real users' session JWTs.
      AUTH_ENFORCE       = var.auth_enforce ? "1" : "0"
      ADMIN_API_SECRET   = var.admin_api_secret
      CLERK_ISSUER       = var.clerk_issuer
      SESSION_JWT_SECRET = var.session_jwt_secret
      # iOS-app identities (handler verifies alongside Clerk): Cognito pool JWTs
      # (Sign in with Apple) + Google ID tokens (empty client id = dark).
      COGNITO_ISSUER         = "https://${aws_cognito_user_pool.mobile.endpoint}"
      COGNITO_CLIENT_ID      = aws_cognito_user_pool_client.ios.id
      LOGIN_RESET_URL        = var.login_reset_url
      LOGIN_EMAIL_FROM       = var.login_email_from
      GOOGLE_OAUTH_CLIENT_ID = var.google_oauth_client_id
      VECTOR_BUCKET          = "${local.prefix}-vectors"
      VECTOR_INDEX           = "pins"
      # Visual search: Titan Multimodal embedding model + vector dimensionality.
      BEDROCK_EMBED_MODEL_ID = "amazon.titan-embed-image-v1"
      VECTOR_DIM             = "1024"
      # MTL value-model re-rank (infra/ml). "" = off; set to the SageMaker
      # serverless endpoint name (e.g. giftmaxxing-dev-mtl) once deployed.
      MTL_ENDPOINT = var.mtl_endpoint
      # Maxi model router (POST /maxi): cheap Amazon Nova by default, escalate to
      # Claude Haiku for agentic shopping (add-to-cart / buy / checkout).
      MAXI_BASE_MODEL_ID     = var.maxi_base_model_id
      MAXI_SHOPPING_MODEL_ID = var.maxi_shopping_model_id
      MAXI_MODEL_ID          = var.maxi_model_id # legacy alias → shopping fallback
      # Maxi budgets: per-interaction token caps + a hard monthly Bedrock $ cap.
      MAXI_MAX_TOKENS               = tostring(var.maxi_max_tokens)
      MAXI_INTERACTION_TOKEN_BUDGET = tostring(var.maxi_interaction_token_budget)
      MAXI_MAX_STEPS                = tostring(var.maxi_max_steps)
      MAXI_MONTHLY_BUDGET_USD       = tostring(var.maxi_monthly_budget_usd)
      # Per-tier prices so monthly $ accounting is right across both models.
      MAXI_BASE_PRICE_IN_PER_1M      = tostring(var.maxi_base_price_in_per_1m)
      MAXI_BASE_PRICE_OUT_PER_1M     = tostring(var.maxi_base_price_out_per_1m)
      MAXI_SHOPPING_PRICE_IN_PER_1M  = tostring(var.maxi_price_in_per_1m)
      MAXI_SHOPPING_PRICE_OUT_PER_1M = tostring(var.maxi_price_out_per_1m)
      MAXI_PRICE_IN_PER_1M           = tostring(var.maxi_price_in_per_1m)  # legacy alias
      MAXI_PRICE_OUT_PER_1M          = tostring(var.maxi_price_out_per_1m) # legacy alias
      # Per-user Maxi rate limit (chats/user/UTC-day) — abuse guard, not a usage cap.
      MAXI_DAILY_LIMIT = tostring(var.maxi_daily_limit)
      # byFeed GSI sharding. 1 = single 'all' partition (unchanged). >1 spreads the
      # global feed across feedPk='all#<n>' shards (write + scatter-gather reads).
      FEED_SHARDS = tostring(var.feed_shards)
    }
  }

  depends_on = [aws_cloudwatch_log_group.api]
}
