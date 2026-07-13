# ── Centralized secrets (AWS Secrets Manager) ─────────────────────────────────
# APNs token-auth credentials live in ONE Secrets Manager secret (JSON) so no
# secret sits in tfvars / env vars / the repo, and any machine with AWS access
# can `terraform apply` without pre-loading them. Terraform reads the secret at
# apply time and injects the values into the SNS platform app (sns-apns.tf).
# Rotate by putting a new secret version (AWS console/CLI) — no code change.
#
# Secret JSON shape:
#   { "apns_private_key": "<.p8 block>", "apns_key_id": "...", "apns_team_id": "..." }
#
# Set apns_secret_name = "" to fall back to the var.apns_* inputs instead (e.g. a
# brand-new environment before the secret exists). See DEPLOY-ANYWHERE.md.
variable "apns_secret_name" {
  description = "AWS Secrets Manager secret id holding APNs token creds as JSON {apns_private_key, apns_key_id, apns_team_id}. Empty string = use the var.apns_* inputs instead."
  type        = string
  default     = "giftmaxxing/dev/apns"
}

data "aws_secretsmanager_secret_version" "apns" {
  count     = var.apns_secret_name != "" ? 1 : 0
  secret_id = var.apns_secret_name
}

locals {
  _apns_sm = var.apns_secret_name != "" ? jsondecode(data.aws_secretsmanager_secret_version.apns[0].secret_string) : {}

  # Prefer the Secrets Manager value; fall back to the tfvars var.apns_* input if
  # a key is absent (or SM is disabled). try() swallows a missing key/decode.
  apns_private_key = try(local._apns_sm.apns_private_key, var.apns_private_key)
  apns_key_id      = try(local._apns_sm.apns_key_id, var.apns_key_id)
  apns_team_id     = try(local._apns_sm.apns_team_id, var.apns_team_id)
}
