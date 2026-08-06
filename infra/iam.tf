data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "api_lambda" {
  name               = "${local.prefix}-api-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# CloudWatch Logs (basic execution).
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.api_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Least-privilege DynamoDB access scoped to our three tables + the GSI.
data "aws_iam_policy_document" "ddb_access" {
  statement {
    sid = "TableAccess"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:BatchGetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:BatchWriteItem",
      "dynamodb:TransactWriteItems",
    ]
    resources = [
      aws_dynamodb_table.users.arn,
      aws_dynamodb_table.posts.arn,
      "${aws_dynamodb_table.posts.arn}/index/*",
      aws_dynamodb_table.ugc_reports.arn,
      "${aws_dynamodb_table.ugc_reports.arn}/index/*",
      aws_dynamodb_table.interactions.arn,
      aws_dynamodb_table.knowledge.arn,
      aws_dynamodb_table.connections.arn,
      aws_dynamodb_table.challenges.arn,
      "${aws_dynamodb_table.challenges.arn}/index/*",
      aws_dynamodb_table.pools.arn,
      "${aws_dynamodb_table.pools.arn}/index/*",
      aws_dynamodb_table.friends.arn,
      aws_dynamodb_table.events.arn,
      "${aws_dynamodb_table.events.arn}/index/*",
      aws_dynamodb_table.graph.arn,
      "${aws_dynamodb_table.graph.arn}/index/*",
      aws_dynamodb_table.analytics.arn,
      "${aws_dynamodb_table.analytics.arn}/index/*",
      # Account deletion (purgeAccount) batch-deletes the user's push-token
      # rows; the mobile_push policy (sns-apns.tf) lacks BatchWriteItem/Scan
      # and is not attached to the App Runner role at all.
      aws_dynamodb_table.devices.arn,
    ]
  }
}

resource "aws_iam_role_policy" "ddb_access" {
  name   = "${local.prefix}-ddb-access"
  role   = aws_iam_role.api_lambda.id
  policy = data.aws_iam_policy_document.ddb_access.json
}

# S3 Vectors read access for the recommendation kNN query path. QueryVectors with
# returnMetadata / a metadata filter also requires GetVectors (per the API).
data "aws_caller_identity" "current" {}

locals {
  vectors_bucket_arn = "arn:aws:s3vectors:${var.region}:${data.aws_caller_identity.current.account_id}:bucket/${local.prefix}-vectors"
}

data "aws_iam_policy_document" "s3vectors_access" {
  statement {
    sid = "VectorRead"
    actions = [
      "s3vectors:QueryVectors",
      "s3vectors:GetVectors",
      "s3vectors:ListVectors",
    ]
    resources = [
      local.vectors_bucket_arn,
      "${local.vectors_bucket_arn}/index/*",
    ]
  }
}

resource "aws_iam_role_policy" "s3vectors_access" {
  name   = "${local.prefix}-s3vectors-access"
  role   = aws_iam_role.api_lambda.id
  policy = data.aws_iam_policy_document.s3vectors_access.json
}

# MTL value-model re-rank (infra/ml): /recommendations invokes the SageMaker
# serverless endpoint when var.mtl_endpoint is set. Scoped to this env's
# endpoints only; created even while the var is "" (harmless, no such endpoint).
data "aws_iam_policy_document" "sagemaker_invoke" {
  statement {
    sid       = "MtlInvoke"
    actions   = ["sagemaker:InvokeEndpoint"]
    resources = ["arn:aws:sagemaker:${var.region}:${data.aws_caller_identity.current.account_id}:endpoint/${local.prefix}-*"]
  }
}

resource "aws_iam_role_policy" "sagemaker_invoke" {
  name   = "${local.prefix}-sagemaker-invoke"
  role   = aws_iam_role.api_lambda.id
  policy = data.aws_iam_policy_document.sagemaker_invoke.json
}

locals {
  # Every model id Maxi might invoke via Converse (base + shopping tiers + the
  # legacy alias), deduped — used to scope the Bedrock InvokeModel policy below.
  maxi_model_ids = distinct([var.maxi_base_model_id, var.maxi_shopping_model_id, var.maxi_model_id])
}

# Bedrock: invoke the Titan Multimodal embedding model to turn an uploaded image
# into a query vector for visual search (POST /visual-search). Foundation-model
# ARNs have an empty account-id segment.
data "aws_iam_policy_document" "bedrock_access" {
  statement {
    sid       = "InvokeTitanEmbed"
    actions   = ["bedrock:InvokeModel"]
    resources = ["arn:aws:bedrock:${var.region}::foundation-model/amazon.titan-embed-image-v1"]
  }

  # Maxi (POST /maxi) invokes its router models via Converse — the cheap Amazon
  # Nova base tier and the Claude Haiku shopping tier. A cross-region inference
  # profile needs InvokeModel on BOTH the profile and the underlying foundation
  # model (region wildcarded, since the profile routes across regions).
  statement {
    sid     = "InvokeMaxiModels"
    actions = ["bedrock:InvokeModel"]
    resources = concat(
      [for m in local.maxi_model_ids : "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:inference-profile/${m}"],
      [for m in local.maxi_model_ids : "arn:aws:bedrock:*::foundation-model/${replace(m, "us.", "")}"]
    )
  }

  # Packaging (POST /packaging) renders one image of the suggested wrap.
  #
  # This is scoped to packaging_image_region, NOT var.region: Bedrock retired
  # Amazon Nova Canvas mid-flight ("marked by provider as Legacy and you have
  # not been actively using the model in the last 30 days") and us-east-1 has no
  # ACTIVE text-to-image model left — every Stability model there edits an
  # existing image rather than generating one. The render leg therefore calls
  # us-west-2. Region is wildcarded on the second ARN so switching the model or
  # region is a variable change, not a policy rewrite.
  statement {
    sid     = "InvokePackagingImageModel"
    actions = ["bedrock:InvokeModel"]
    resources = [
      "arn:aws:bedrock:${var.packaging_image_region}::foundation-model/${var.packaging_image_model_id}",
      "arn:aws:bedrock:${var.packaging_image_region}:${data.aws_caller_identity.current.account_id}:inference-profile/*",
    ]
  }
}

resource "aws_iam_role_policy" "bedrock_access" {
  name   = "${local.prefix}-bedrock-access"
  role   = aws_iam_role.api_lambda.id
  policy = data.aws_iam_policy_document.bedrock_access.json
}

data "aws_iam_policy_document" "login_email" {
  statement {
    sid       = "SendLoginLockoutEmail"
    actions   = ["ses:SendEmail"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "login_email" {
  name   = "${local.prefix}-login-email"
  role   = aws_iam_role.api_lambda.id
  policy = data.aws_iam_policy_document.login_email.json
}

# API-side upload signing + account-deletion cleanup. Raw objects are never
# readable through CloudFront; the moderation workers alone promote them.
data "aws_iam_policy_document" "ugc_api_media" {
  statement {
    actions = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
    resources = [
      "${aws_s3_bucket.media.arn}/ugc/raw/*",
      "${aws_s3_bucket.media.arn}/ugc/posters-raw/*",
      "${aws_s3_bucket.media.arn}/ugc/public/*",
      "${aws_s3_bucket.media.arn}/avatars/raw/*",
      "${aws_s3_bucket.media.arn}/avatars/public/*",
      # Generated packaging renders (POST /packaging). Model output only —
      # never a user upload — so it goes straight to the public prefix.
      "${aws_s3_bucket.media.arn}/wrap/public/*",
    ]
  }

  statement {
    actions   = ["rekognition:DetectModerationLabels"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "api_ugc_media" {
  name   = "${local.prefix}-api-ugc-media"
  role   = aws_iam_role.api_lambda.id
  policy = data.aws_iam_policy_document.ugc_api_media.json
}
