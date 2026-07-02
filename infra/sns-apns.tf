# ── SNS Platform Application for APNs (iOS push notifications) ────────────────
# Extends the existing reminders system to deliver push notifications to iOS
# devices. The device token table stores APNs tokens registered by the mobile app
# via POST /mobile/device.

resource "aws_sns_platform_application" "ios_push" {
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

  statement {
    sid     = "SNSPublishPush"
    actions = ["sns:Publish"]
    resources = [aws_sns_platform_application.ios_push.arn]
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
