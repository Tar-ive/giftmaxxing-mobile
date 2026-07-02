// Core declarations restored verbatim from 392869e — the c51031c merge kept
// only the mobile-branch block and dropped these, but lambda.tf, apprunner.tf,
// budgets.tf, cloudfront.tf, killswitch.tf, monitoring.tf, … still reference
// them (and terraform.tfvars sets several). local.prefix and var.prefix
// intentionally resolve to the same "giftmaxxing-dev" so old and new files
// name resources identically.
variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "env" {
  description = "Environment name (used in resource name prefixes)"
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name prefix for resources"
  type        = string
  default     = "giftmaxxing"
}

locals {
  prefix = "${var.project}-${var.env}"
}

variable "cors_allow_origins" {
  description = "Allowed CORS origins for the HTTP API. This is an unauthenticated public read API, so '*' lets the Vercel prod + preview domains call it from the browser. Restrict to specific origins (e.g. your Vercel domain + http://localhost:3000) to lock down browser callers."
  type        = list(string)
  default     = ["*"]
}

variable "enable_cost_allocation_tags" {
  description = "Activate Project/Env as Cost Allocation Tags for Cost Explorer (see cost.tf). Requires the management/payer account AND the tag key to already be visible in Billing (~24h after first use); leave false otherwise to avoid apply errors."
  type        = bool
  default     = false
}

variable "alert_email" {
  description = "Email for cost/budget alerts (subscribes to the cost-alerts SNS topic; see budgets.tf). Leave empty to skip. Set it in terraform.tfvars (gitignored) or via -var. After apply you MUST click the confirmation link AWS emails you, or no alerts arrive."
  type        = string
  default     = ""
}

variable "cost_alert_emails" {
  description = "Addresses emailed DIRECTLY by the monthly budget (in addition to var.alert_email's SNS subscription) for the actual-threshold + $500 forecasted notifications. Codifies the recipients so `terraform apply` never again wipes emails added by hand in the AWS console. Unlike SNS, budget emails need NO confirmation. Set in terraform.tfvars (gitignored)."
  type        = list(string)
  default     = []
}

variable "alert_sms_number" {
  description = "Optional phone number in E.164 format (e.g. +15551234567) for SMS cost alerts. Leave empty to skip. SNS SMS may require moving the account out of the SMS sandbox / verifying the number first."
  type        = string
  default     = ""
}

# ── Phase 2: kill switch + real-time tripwires (see killswitch.tf) ────────────
variable "api_reserved_concurrency" {
  description = "Reserved concurrency ceiling for the API Lambda — a baseline guard so a runaway/traffic spike can't balloon Lambda + DynamoDB cost. -1 = unreserved (no cap). The $1,000 kill switch pauses expensive AI routes on top of this. NOTE: a reservation needs the account's Lambda 'Concurrent executions' quota above 10 (AWS always keeps 10 unreserved); raise it via Service Quotas to use a positive value."
  type        = number
  default     = -1
}

variable "maxi_base_model_id" {
  description = "Bedrock model / inference-profile id for Maxi's BASE (default) tier — the cheapest option, used for browsing, gift discovery, taste chat, and Q&A. Default = Amazon Nova Lite (us cross-region inference profile)."
  type        = string
  default     = "us.amazon.nova-lite-v1:0"
}

variable "clerk_issuer" {
  description = "Clerk Frontend API issuer URL used to verify session JWTs (token iss must match). Derived from NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY."
  type        = string
  default     = "https://usable-mammoth-92.clerk.accounts.dev"
}

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

variable "maxi_shopping_model_id" {
  description = "Bedrock model / inference-profile id for Maxi's SHOPPING tier — used when an agentic shopping experience (add-to-cart / buy / checkout) is triggered. Default = Claude Haiku 4.5 (us cross-region inference profile)."
  type        = string
  default     = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
}

# DEPRECATED alias kept for back-compat: maps to env MAXI_MODEL_ID, which the
# handler now uses ONLY as a fallback for maxi_shopping_model_id. Prefer the two
# tier-specific vars above.
variable "maxi_model_id" {
  description = "DEPRECATED — legacy single-model id. Now only a fallback for maxi_shopping_model_id (env MAXI_MODEL_ID). Prefer maxi_base_model_id + maxi_shopping_model_id."
  type        = string
  default     = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
}

# ── Maxi budgets (POST /maxi): per-interaction token caps + monthly Bedrock $ cap
variable "maxi_max_tokens" {
  description = "Maxi per-call OUTPUT token cap (Bedrock Converse maxTokens)."
  type        = number
  default     = 768
}

variable "maxi_interaction_token_budget" {
  description = "Hard cap on TOTAL tokens (input+output) summed across Maxi's tool-use loop for ONE /maxi request. When exceeded, the loop stops."
  type        = number
  default     = 30000
}

variable "maxi_max_steps" {
  description = "Max Bedrock Converse round-trips (tool-use steps) per Maxi interaction."
  type        = number
  default     = 5
}

variable "maxi_monthly_budget_usd" {
  description = "Hard MONTHLY Bedrock budget for Maxi (estimated USD). When month-to-date Maxi spend reaches this, /maxi returns 503 and the client falls back to the offline responder. 0 = unlimited."
  type        = number
  default     = 25
}

variable "maxi_daily_limit" {
  description = "Per-user Maxi rate limit: max /maxi chats per user per UTC day. Blocks a single account from running away with cost/abuse without throttling normal use. Keyed by the verified Clerk sub (admin/ingest token bypasses). 0 = unlimited."
  type        = number
  default     = 50
}

# Maxi SHOPPING-tier (Haiku) prices. Fed to the handler as both the legacy
# MAXI_PRICE_* and the MAXI_SHOPPING_PRICE_* envs.
variable "maxi_price_in_per_1m" {
  description = "Bedrock price (USD) per 1M INPUT tokens for Maxi's SHOPPING model (Haiku), used to estimate spend vs maxi_monthly_budget_usd. VERIFY against current Bedrock pricing for Claude Haiku 4.5."
  type        = number
  default     = 1.0
}

variable "maxi_price_out_per_1m" {
  description = "Bedrock price (USD) per 1M OUTPUT tokens for Maxi's SHOPPING model (Haiku). VERIFY against current Bedrock pricing for Claude Haiku 4.5."
  type        = number
  default     = 5.0
}

# Maxi BASE-tier (Nova) prices for accurate monthly $ accounting when a request
# stays on the cheap default model.
variable "maxi_base_price_in_per_1m" {
  description = "Bedrock price (USD) per 1M INPUT tokens for Maxi's BASE model (Amazon Nova Lite). VERIFY against current Bedrock Nova pricing."
  type        = number
  default     = 0.06
}

variable "maxi_base_price_out_per_1m" {
  description = "Bedrock price (USD) per 1M OUTPUT tokens for Maxi's BASE model (Amazon Nova Lite). VERIFY against current Bedrock Nova pricing."
  type        = number
  default     = 0.24
}

variable "alarm_bedrock_invocations_5min" {
  description = "Real-time tripwire: trip the kill switch if Bedrock (Titan) invocations exceed this in a 5-min window. Tune to your normal visual-search volume."
  type        = number
  default     = 500
}

variable "alarm_maxi_invocations_5min" {
  description = "Real-time tripwire: trip the kill switch if Maxi (Bedrock Converse) invocations exceed this in a 5-min window, summed PER ModelId. Catches a runaway tool-use loop or traffic spike. Tune to expected Maxi chat volume (each interaction = up to maxi_max_steps model calls)."
  type        = number
  default     = 300
}

variable "alarm_api_requests_5min" {
  description = "Real-time tripwire: trip the kill switch if API Gateway requests exceed this in a 5-min window (~166 req/s at 50000)."
  type        = number
  default     = 50000
}

variable "alarm_apprunner_concurrency" {
  description = "Real-time tripwire: DEGRADE non-essential AI (Maxi cheap+short; pause visual search / vector recs / pins) when App Runner SERVICE-WIDE concurrent requests (AWS/AppRunner 'Concurrency', Maximum, dimensioned by ServiceName/ServiceID) exceed this for 3 consecutive minutes, then AUTO-RESUME when it clears. The service ceiling is max_concurrency (100) x max_size (5) = 500 concurrent, so tune relative to that (e.g. 200 ~= 40%). Raise it as you scale."
  type        = number
  default     = 150
}

variable "monthly_budget_limit_usd" {
  description = "Monthly AWS Budget limit (USD) AND the hard kill-switch trigger point: at this month-to-date spend the budget publishes to the cost-killswitch topic -> breaker PAUSES non-essential features (human resume only). The $10/$50/$100 actual + $500 forecasted heads-up alerts are unchanged. Raise this to scale up; e.g. 3000 for ~500 users."
  type        = number
  default     = 1000
}

variable "feed_shards" {
  description = "Number of partitions for the byFeed GSI hot 'all' key. 1 (default) = single partition (current behavior, unchanged). >1 = the handler writes feedPk='all#<hash(postId) %% N>' and scatter-gathers reads across all shards, spreading the global feed past one GSI partition's ~3k RCU/s ceiling. After raising this, terraform apply THEN re-run `node ingest-pins.mjs` to re-key existing posts into shards."
  type        = number
  default     = 1
}

# ── API authentication (see handler.mjs auth gate) ───────────────────────────
variable "auth_enforce" {
  description = "Enforce API auth in the handler (Clerk JWT or x-admin-token). Ship the auth code with this false, deploy the token-sending client, then flip true. Set false again for an INSTANT rollback (one apply, no code change)."
  type        = bool
  default     = false
}

variable "admin_api_secret" {
  description = "Shared secret for the admin/ingest path (x-admin-token header) — the admin 'password'. Used by the local admin-dev bypass + ingest scripts; real users authenticate via Clerk JWT instead. Set in terraform.tfvars (gitignored). Empty disables the admin path."
  type        = string
  default     = ""
  sensitive   = true
}

variable "google_oauth_client_id" {
  description = "Google OAuth client id used as the JWT audience when the API verifies iOS Google Sign-In ID tokens. Must match GoogleOAuthConfig.clientID in the app. Empty (default) keeps Google-token auth dark; Cognito (Sign in with Apple) works regardless."
  type        = string
  default     = ""
}

# ── Sign in with Apple (Cognito IdP) ──────────────────────────────────────────
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
