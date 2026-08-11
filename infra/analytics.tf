resource "aws_dynamodb_table" "analytics" {
  name             = "${var.prefix}-analytics"
  billing_mode     = "PAY_PER_REQUEST"
  hash_key         = "userId"
  range_key        = "sk"
  stream_enabled   = true
  stream_view_type = "NEW_IMAGE"

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  attribute {
    name = "type"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  # Query by event type across all users (e.g. "all swipe_right events today")
  global_secondary_index {
    name            = "byType"
    hash_key        = "type"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  tags = {
    Project = "giftmaxxing"
    Purpose = "mobile-analytics"
  }
}

output "analytics_table_name" {
  description = "DynamoDB table for mobile behavioral analytics"
  value       = aws_dynamodb_table.analytics.name
}

output "analytics_table_arn" {
  description = "ARN for IAM policy attachment"
  value       = aws_dynamodb_table.analytics.arn
}
