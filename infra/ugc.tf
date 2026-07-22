# UGC moderation pipeline:
# private S3 upload -> image/video moderation -> approved public copy.

resource "aws_sns_topic" "ugc_rekognition" {
  # Rekognition's managed integration expects an AmazonRekognition prefix.
  name = "AmazonRekognition-${local.prefix}-ugc"
}

data "aws_iam_policy_document" "rekognition_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["rekognition.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rekognition_publish" {
  name               = "${local.prefix}-rekognition-publish"
  assume_role_policy = data.aws_iam_policy_document.rekognition_assume.json
}

resource "aws_iam_role_policy" "rekognition_publish" {
  name = "${local.prefix}-rekognition-publish"
  role = aws_iam_role.rekognition_publish.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sns:Publish"
      Resource = aws_sns_topic.ugc_rekognition.arn
    }]
  })
}

resource "aws_iam_role" "ugc_worker" {
  name               = "${local.prefix}-ugc-worker"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "ugc_worker_logs" {
  role       = aws_iam_role.ugc_worker.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "ugc_worker" {
  name = "${local.prefix}-ugc-worker"
  role = aws_iam_role.ugc_worker.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:UpdateItem"]
        Resource = aws_dynamodb_table.posts.arn
      },
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = [
          "${aws_s3_bucket.media.arn}/ugc/raw/*",
          "${aws_s3_bucket.media.arn}/ugc/posters-raw/*",
          "${aws_s3_bucket.media.arn}/ugc/public/*",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "rekognition:DetectLabels",
          "rekognition:DetectModerationLabels",
          "rekognition:StartContentModeration",
          "rekognition:GetContentModeration",
          "rekognition:StartLabelDetection",
          "rekognition:GetLabelDetection",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.rekognition_publish.arn
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "ugc_ingest" {
  name              = "/aws/lambda/${local.prefix}-ugc-ingest"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "ugc_results" {
  name              = "/aws/lambda/${local.prefix}-ugc-results"
  retention_in_days = 14
}

resource "aws_lambda_function" "ugc_ingest" {
  function_name    = "${local.prefix}-ugc-ingest"
  role             = aws_iam_role.ugc_worker.arn
  runtime          = "nodejs20.x"
  handler          = "ugc-ingest.handler"
  filename         = data.archive_file.api.output_path
  source_code_hash = data.archive_file.api.output_base64sha256
  timeout          = 60
  memory_size      = 512

  environment {
    variables = {
      POSTS_TABLE               = aws_dynamodb_table.posts.name
      MEDIA_BUCKET              = aws_s3_bucket.media.id
      UGC_REKOGNITION_TOPIC_ARN = aws_sns_topic.ugc_rekognition.arn
      UGC_REKOGNITION_ROLE_ARN  = aws_iam_role.rekognition_publish.arn
      FEED_SHARDS               = tostring(var.feed_shards)
    }
  }
  depends_on = [aws_cloudwatch_log_group.ugc_ingest, aws_iam_role_policy.ugc_worker]
}

resource "aws_lambda_function" "ugc_results" {
  function_name    = "${local.prefix}-ugc-results"
  role             = aws_iam_role.ugc_worker.arn
  runtime          = "nodejs20.x"
  handler          = "ugc-results.handler"
  filename         = data.archive_file.api.output_path
  source_code_hash = data.archive_file.api.output_base64sha256
  timeout          = 120
  memory_size      = 512

  environment {
    variables = {
      POSTS_TABLE  = aws_dynamodb_table.posts.name
      MEDIA_BUCKET = aws_s3_bucket.media.id
      FEED_SHARDS  = tostring(var.feed_shards)
    }
  }
  depends_on = [aws_cloudwatch_log_group.ugc_results, aws_iam_role_policy.ugc_worker]
}

resource "aws_lambda_permission" "ugc_from_s3" {
  statement_id  = "AllowS3UGCUploads"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ugc_ingest.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.media.arn
}

resource "aws_s3_bucket_notification" "ugc" {
  bucket = aws_s3_bucket.media.id
  lambda_function {
    lambda_function_arn = aws_lambda_function.ugc_ingest.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "ugc/raw/"
  }
  depends_on = [aws_lambda_permission.ugc_from_s3]
}

resource "aws_sns_topic_subscription" "ugc_results" {
  topic_arn = aws_sns_topic.ugc_rekognition.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.ugc_results.arn
}

resource "aws_lambda_permission" "ugc_from_sns" {
  statement_id  = "AllowSNSUGCResults"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ugc_results.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.ugc_rekognition.arn
}

resource "aws_cloudwatch_metric_alarm" "ugc_failures" {
  alarm_name          = "${local.prefix}-ugc-worker-errors"
  alarm_description   = "UGC moderation worker errors need investigation."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { FunctionName = aws_lambda_function.ugc_ingest.function_name }
  alarm_actions       = [aws_sns_topic.cost_alerts.arn]
}
