output "cognito_user_pool_id" {
  description = "Cognito User Pool ID for the iOS app"
  value       = aws_cognito_user_pool.mobile.id
}

output "cognito_client_id" {
  description = "Cognito App Client ID for the iOS app"
  value       = aws_cognito_user_pool_client.ios.id
}

output "cognito_domain" {
  description = "Cognito hosted UI domain"
  value       = aws_cognito_user_pool_domain.mobile.domain
}

output "cognito_issuer" {
  description = "Cognito JWT issuer URL (add to Lambda COGNITO_ISSUER env var)"
  value       = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.mobile.id}"
}

output "devices_table_name" {
  description = "DynamoDB table for device tokens"
  value       = aws_dynamodb_table.devices.name
}

output "sns_platform_app_arn" {
  description = "SNS Platform Application ARN for iOS push"
  value       = aws_sns_platform_application.ios_push.arn
}
