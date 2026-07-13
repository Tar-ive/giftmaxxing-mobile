# ── SNS Platform Application for APNs (iOS push notifications) ────────────────
# Extends the existing reminders system to deliver push notifications to iOS
# devices. The device token table stores APNs tokens registered by the mobile app
# via POST /mobile/device.

# TOKEN-based APNs auth (.p8 signing key). SNS needs the signing key contents
# (platform_credential), its Key ID (platform_principal), the Apple Team ID, and
# the app bundle id. Created only when the key + Key ID + Team ID are all present
# — SNS rejects partial/empty credentials and would fail the whole apply.
# Platform "APNS" = production gateway (TestFlight / App Store builds).
resource "aws_sns_platform_application" "ios_push" {
  # Values resolve from Secrets Manager (secrets.tf) with a tfvars fallback.
  # nonsensitive() is required because count can't depend on sensitive values;
  # we only expose the boolean "are all three present", never the values.
  count = nonsensitive(local.apns_private_key != "" && local.apns_key_id != "" && local.apns_team_id != "") ? 1 : 0

  name                     = "${var.prefix}-ios-push"
  platform                 = "APNS"
  platform_credential      = local.apns_private_key # .p8 signing key contents
  platform_principal       = local.apns_key_id      # signing Key ID
  apple_platform_team_id   = local.apns_team_id
  apple_platform_bundle_id = var.apns_bundle_id

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
    sid = "DevicesTableAccess"
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
    sid = "SNSCreateEndpoint"
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
