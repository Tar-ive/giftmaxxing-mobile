resource "aws_dynamodb_table" "catalog_entities" {
  name         = "${local.prefix}-catalog-entities"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "entityId"

  attribute {
    name = "entityId"
    type = "S"
  }
  attribute {
    name = "kind"
    type = "S"
  }
  attribute {
    name = "status"
    type = "S"
  }

  global_secondary_index {
    name            = "byKind"
    hash_key        = "kind"
    range_key       = "status"
    projection_type = "ALL"
  }
  point_in_time_recovery {
    enabled = true
  }
  tags = { Project = "giftmaxxing", Purpose = "recommender-catalog" }
}

resource "aws_dynamodb_table" "catalog_edges" {
  name         = "${local.prefix}-catalog-edges"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "fromId"
  range_key    = "edgeKey"

  attribute {
    name = "fromId"
    type = "S"
  }
  attribute {
    name = "edgeKey"
    type = "S"
  }
  attribute {
    name = "toId"
    type = "S"
  }
  attribute {
    name = "reverseKey"
    type = "S"
  }

  global_secondary_index {
    name            = "reverse"
    hash_key        = "toId"
    range_key       = "reverseKey"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }
  tags = { Project = "giftmaxxing", Purpose = "recommender-graph" }
}

resource "aws_dynamodb_table" "taste_profiles" {
  name         = "${local.prefix}-taste-profiles"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "profileId"

  attribute {
    name = "profileId"
    type = "S"
  }
  point_in_time_recovery {
    enabled = true
  }
  tags = { Project = "giftmaxxing", Purpose = "recommender-profiles" }
}

resource "aws_cloudwatch_log_group" "taste_profile_stream" {
  name              = "/aws/lambda/${local.prefix}-taste-profile-stream"
  retention_in_days = 14
}

resource "aws_lambda_function" "taste_profile_stream" {
  function_name    = "${local.prefix}-taste-profile-stream"
  role             = aws_iam_role.api_lambda.arn
  runtime          = "nodejs20.x"
  handler          = "taste-profile-stream.handler"
  filename         = data.archive_file.api.output_path
  source_code_hash = data.archive_file.api.output_base64sha256
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      TASTE_PROFILES_TABLE   = aws_dynamodb_table.taste_profiles.name
      CATALOG_ENTITIES_TABLE = aws_dynamodb_table.catalog_entities.name
      POSTS_TABLE            = aws_dynamodb_table.posts.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.taste_profile_stream]
}

data "aws_iam_policy_document" "analytics_stream_read" {
  statement {
    actions   = ["dynamodb:DescribeStream", "dynamodb:GetRecords", "dynamodb:GetShardIterator", "dynamodb:ListStreams"]
    resources = [aws_dynamodb_table.analytics.stream_arn]
  }
}

resource "aws_iam_role_policy" "analytics_stream_read" {
  name   = "${local.prefix}-analytics-stream-read"
  role   = aws_iam_role.api_lambda.id
  policy = data.aws_iam_policy_document.analytics_stream_read.json
}

resource "aws_lambda_event_source_mapping" "taste_profile_stream" {
  event_source_arn                   = aws_dynamodb_table.analytics.stream_arn
  function_name                      = aws_lambda_function.taste_profile_stream.arn
  starting_position                  = "LATEST"
  batch_size                         = 50
  maximum_batching_window_in_seconds = 5
  bisect_batch_on_function_error     = true
  maximum_retry_attempts             = 3
  function_response_types            = ["ReportBatchItemFailures"]
  depends_on                         = [aws_iam_role_policy.analytics_stream_read]
}

resource "aws_cloudwatch_metric_alarm" "taste_profile_stream_errors" {
  alarm_name          = "${local.prefix}-taste-profile-stream-errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  dimensions          = { FunctionName = aws_lambda_function.taste_profile_stream.function_name }
}

resource "aws_s3_bucket" "recommender_ml" {
  bucket = "${local.prefix}-recommender-ml-${data.aws_caller_identity.current.account_id}"
  tags   = { Project = "giftmaxxing", Purpose = "recommender-training" }
}

resource "aws_s3_bucket_versioning" "recommender_ml" {
  bucket = aws_s3_bucket.recommender_ml.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "recommender_ml" {
  bucket = aws_s3_bucket.recommender_ml.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "recommender_ml" {
  bucket                  = aws_s3_bucket.recommender_ml.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "archive_file" "recommender_ml" {
  type        = "zip"
  source_dir  = "${path.module}/ml"
  output_path = "${path.module}/build/recommender-ml.zip"
  excludes = [
    ".venv",
    "__pycache__",
    "data",
    "model",
    "notebooks",
    "clusters.json",
  ]
}

resource "aws_s3_object" "recommender_ml_source" {
  bucket      = aws_s3_bucket.recommender_ml.id
  key         = "source/recommender-ml.zip"
  source      = data.archive_file.recommender_ml.output_path
  source_hash = data.archive_file.recommender_ml.output_base64sha256
}

resource "aws_s3_object" "recommender_active_manifest" {
  bucket       = aws_s3_bucket.recommender_ml.id
  key          = "models/active.json"
  content_type = "application/json"
  content      = jsonencode({ version = "deterministic-cosine-v1", approvedAt = null, model = null, previous = null })
  lifecycle { ignore_changes = [content] }
}

data "aws_iam_policy_document" "sagemaker_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "recommender_sagemaker" {
  name               = "${local.prefix}-recommender-sagemaker"
  assume_role_policy = data.aws_iam_policy_document.sagemaker_assume.json
}

resource "aws_iam_role_policy" "recommender_sagemaker" {
  name = "${local.prefix}-recommender-sagemaker"
  role = aws_iam_role.recommender_sagemaker.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"], Resource = [aws_s3_bucket.recommender_ml.arn, "${aws_s3_bucket.recommender_ml.arn}/*"] },
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken", "ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"], Resource = "*" }
    ]
  })
}

data "aws_iam_policy_document" "codebuild_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "recommender_codebuild" {
  name               = "${local.prefix}-recommender-codebuild"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume.json
}

resource "aws_iam_role_policy" "recommender_codebuild" {
  name = "${local.prefix}-recommender-codebuild"
  role = aws_iam_role.recommender_codebuild.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = "*" },
      { Effect = "Allow", Action = ["dynamodb:Scan", "dynamodb:Query", "dynamodb:GetItem", "dynamodb:BatchGetItem"], Resource = [aws_dynamodb_table.analytics.arn, "${aws_dynamodb_table.analytics.arn}/index/*", aws_dynamodb_table.posts.arn, aws_dynamodb_table.challenges.arn, aws_dynamodb_table.taste_profiles.arn] },
      { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"], Resource = [aws_s3_bucket.recommender_ml.arn, "${aws_s3_bucket.recommender_ml.arn}/*"] },
      { Effect = "Allow", Action = ["s3vectors:GetVectors", "s3vectors:ListVectors"], Resource = [local.vectors_bucket_arn, "${local.vectors_bucket_arn}/index/*"] },
      { Effect = "Allow", Action = ["sagemaker:CreateTrainingJob", "sagemaker:DescribeTrainingJob", "sagemaker:CreateModelPackage", "sagemaker:DescribeModelPackage", "sagemaker:ListModelPackages"], Resource = "*" },
      { Effect = "Allow", Action = "iam:PassRole", Resource = aws_iam_role.recommender_sagemaker.arn }
    ]
  })
}

resource "aws_sagemaker_model_package_group" "recommender" {
  model_package_group_name        = "${local.prefix}-recommender"
  model_package_group_description = "Mixer v2 candidates; promotion is always manual"
}

resource "aws_codebuild_project" "recommender_training" {
  name         = "${local.prefix}-recommender-training"
  service_role = aws_iam_role.recommender_codebuild.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }
  source {
    type      = "NO_SOURCE"
    buildspec = <<-YAML
      version: 0.2
      phases:
        install:
          commands:
            - python3 -m pip install --quiet boto3 numpy
        build:
          commands:
            - aws s3 cp s3://$RECOMMENDER_ML_BUCKET/source/recommender-ml.zip /tmp/recommender-ml.zip
            - mkdir -p /tmp/recommender-ml && cd /tmp/recommender-ml
            - unzip -q /tmp/recommender-ml.zip
            - python3 run_recommender_training.py --reason "$TRAINING_REASON" --wait
    YAML
  }
  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    environment_variable {
      name  = "AWS_REGION"
      value = var.region
    }
    environment_variable {
      name  = "ANALYTICS_TABLE"
      value = aws_dynamodb_table.analytics.name
    }
    environment_variable {
      name  = "POSTS_TABLE"
      value = aws_dynamodb_table.posts.name
    }
    environment_variable {
      name  = "RECOMMENDER_ML_BUCKET"
      value = aws_s3_bucket.recommender_ml.id
    }
    environment_variable {
      name  = "RECOMMENDER_SAGEMAKER_ROLE_ARN"
      value = aws_iam_role.recommender_sagemaker.arn
    }
    environment_variable {
      name  = "RECOMMENDER_MODEL_PACKAGE_GROUP"
      value = aws_sagemaker_model_package_group.recommender.model_package_group_name
    }
    environment_variable {
      name  = "TRAINING_REASON"
      value = "scheduled"
    }
  }
  build_timeout = 180
}

data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "recommender_scheduler" {
  name               = "${local.prefix}-recommender-scheduler"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}

resource "aws_iam_role_policy" "recommender_scheduler" {
  name   = "${local.prefix}-recommender-scheduler"
  role   = aws_iam_role.recommender_scheduler.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "codebuild:StartBuild", Resource = aws_codebuild_project.recommender_training.arn }] })
}

resource "aws_scheduler_schedule" "recommender_training" {
  name                = "${local.prefix}-recommender-every-three-days"
  schedule_expression = "rate(3 days)"
  flexible_time_window {
    mode = "OFF"
  }
  target {
    arn      = aws_codebuild_project.recommender_training.arn
    role_arn = aws_iam_role.recommender_scheduler.arn
    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 2
    }
  }
}

data "aws_iam_policy_document" "recommender_model_read" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.recommender_ml.arn}/models/*"]
  }
}

resource "aws_iam_role_policy" "recommender_model_read" {
  name   = "${local.prefix}-recommender-model-read"
  role   = aws_iam_role.api_lambda.id
  policy = data.aws_iam_policy_document.recommender_model_read.json
}

resource "aws_iam_role_policy" "apprunner_recommender_model_read" {
  name   = "${local.prefix}-apprunner-recommender-model-read"
  role   = aws_iam_role.apprunner_instance.id
  policy = data.aws_iam_policy_document.recommender_model_read.json
}

output "recommender_training_project" { value = aws_codebuild_project.recommender_training.name }
output "recommender_schedule" { value = aws_scheduler_schedule.recommender_training.name }
