# ── SNS Platform Application for APNs (iOS push notifications) ────────────────
# Extends the existing reminders system to deliver push notifications to iOS
# devices. The device token table stores APNs tokens registered by the mobile app
# via POST /mobile/device.

# Created only when APNs credentials are supplied — SNS rejects empty ones and
# would fail the whole apply.
resource "aws_sns_platform_application" "ios_push" {
  count = var.apns_private_key != "" ? 1 : 0

  name                = "${var.prefix}-ios-push"
  platform            = "APNS"
  platform_credential = var.apns_private_key
  platform_principal  = var.apns_certificate

  event_delivery_failure_topic_arn = aws_sns_topic.push_failures.arn

  success_feedback_sample_rate = "10"
}

resource "aws_sns_topic" "push_failures" {
  name = "${var.prefix}-push-failures"
}

# ── Device tokens table ───────────────────────────────────────────────────────
# Stores APNs device tokens for push notification delivery. PK: userId,
# SK: deviceId (allows multiple devices per user). TTL auto-cleans stale tokens.
resource "aws_dynamodb_table" "devices" {
  name         = "${var.prefix}-devices"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"
  range_key    = "deviceId"

  attribute {
    name = "userId"
    type = "S"
  }
  attribute {
    name = "deviceId"
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

# Grant the API Lambda access to the devices table and SNS publish
data "aws_iam_policy_document" "mobile_push" {
  statement {
    sid     = "DevicesTableAccess"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
    ]
    resources = [aws_dynamodb_table.devices.arn]
  }

  dynamic "statement" {
    for_each = aws_sns_platform_application.ios_push[*].arn
    content {
      sid       = "SNSPublishPush"
      actions   = ["sns:Publish"]
      resources = [statement.value]
    }
  }

  statement {
    sid     = "SNSCreateEndpoint"
    actions = [
      "sns:CreatePlatformEndpoint",
      "sns:GetEndpointAttributes",
      "sns:SetEndpointAttributes",
    ]
    resources = ["*"]
  }
}

# Attach the push policy to the API Lambda role (also used by the reminders
# Lambda — one attachment covers both). Without this the policy document above
# was orphaned: registered tokens could never be read and publishes were denied.
resource "aws_iam_role_policy" "mobile_push" {
  name   = "${var.prefix}-mobile-push"
  role   = aws_iam_role.api_lambda.id
  policy = data.aws_iam_policy_document.mobile_push.json
}
