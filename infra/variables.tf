variable "prefix" {
  description = "Resource name prefix"
  type        = string
  default     = "giftmaxxing-dev"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# ── Apple Sign In (Cognito) ───────────────────────────────────────────────────
variable "apple_client_id" {
  description = "Apple Services ID (e.g. com.giftmaxxing.ios)"
  type        = string
  default     = ""
}

variable "apple_team_id" {
  description = "Apple Developer Team ID"
  type        = string
  default     = ""
}

variable "apple_key_id" {
  description = "Apple Sign In key ID"
  type        = string
  default     = ""
}

variable "apple_private_key" {
  description = "Apple Sign In private key (PEM)"
  type        = string
  default     = ""
  sensitive   = true
}

# ── APNs (Push Notifications) ─────────────────────────────────────────────────
variable "apns_private_key" {
  description = "APNs private key (.p8)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "apns_certificate" {
  description = "APNs certificate (.pem)"
  type        = string
  default     = ""
  sensitive   = true
}

# ── Cognito OAuth ─────────────────────────────────────────────────────────────
variable "cognito_callback_urls" {
  description = "OAuth callback URLs for Cognito"
  type        = list(string)
  default     = ["giftmaxxing://auth/callback"]
}

variable "cognito_logout_urls" {
  description = "OAuth logout URLs for Cognito"
  type        = list(string)
  default     = ["giftmaxxing://auth/logout"]
}
