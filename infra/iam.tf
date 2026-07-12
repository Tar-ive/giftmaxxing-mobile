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
    ]
    resources = [
      aws_dynamodb_table.users.arn,
      aws_dynamodb_table.posts.arn,
      "${aws_dynamodb_table.posts.arn}/index/*",
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
}

resource "aws_iam_role_policy" "bedrock_access" {
  name   = "${local.prefix}-bedrock-access"
  role   = aws_iam_role.api_lambda.id
  policy = data.aws_iam_policy_document.bedrock_access.json
}
