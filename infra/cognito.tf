# ── Cognito User Pool (mobile auth — Sign in with Apple) ──────────────────────
# iOS app authenticates via Sign in with Apple → Cognito exchanges the Apple ID
# token for a Cognito JWT. The API Lambda validates this JWT alongside the
# existing Clerk JWT (web). Both issuers are trusted; the Lambda checks whichever
# is present in the Authorization header.

resource "aws_cognito_user_pool" "mobile" {
  name = "${var.prefix}-mobile"

  auto_verified_attributes = ["email"]

  schema {
    attribute_data_type = "String"
    name                = "email"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  password_policy {
    minimum_length    = 8
    require_lowercase = false
    require_numbers   = false
    require_symbols   = false
    require_uppercase = false
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  user_pool_add_ons {
    advanced_security_mode = "OFF"
  }
}

# Sign in with Apple identity provider — only when the Apple credentials are
# actually supplied (empty tfvars would fail the whole apply otherwise; the
# pool itself works without it, which is all the API's JWT verification needs).
resource "aws_cognito_identity_provider" "apple" {
  count = var.apple_client_id != "" && var.apple_private_key != "" ? 1 : 0

  user_pool_id  = aws_cognito_user_pool.mobile.id
  provider_name = "SignInWithApple"
  provider_type = "SignInWithApple"

  provider_details = {
    client_id                     = var.apple_client_id
    team_id                       = var.apple_team_id
    key_id                        = var.apple_key_id
    private_key                   = var.apple_private_key
    authorize_scopes              = "email name"
    oidc_issuer                   = "https://appleid.apple.com"
    attributes_url_add_attributes = "false"
  }

  attribute_mapping = {
    email    = "email"
    username = "sub"
  }
}

# App client (public — no secret, for mobile)
resource "aws_cognito_user_pool_client" "ios" {
  name         = "${var.prefix}-ios"
  user_pool_id = aws_cognito_user_pool.mobile.id

  generate_secret = false

  # Cognito rejects listing an IdP that doesn't exist — fall back to native
  # accounts until the Apple provider is configured.
  supported_identity_providers = var.apple_client_id != "" && var.apple_private_key != "" ? ["SignInWithApple"] : ["COGNITO"]

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  allowed_oauth_flows_user_pool_client = true

  callback_urls = var.cognito_callback_urls
  logout_urls   = var.cognito_logout_urls

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_CUSTOM_AUTH",
    # Admin-side password auth (needs AWS creds) — lets ops mint test JWTs:
    #   aws cognito-idp admin-initiate-auth --auth-flow ADMIN_USER_PASSWORD_AUTH ...
    "ALLOW_ADMIN_USER_PASSWORD_AUTH",
    # Client-side email+password (InitiateAuth over TLS, no AWS creds) — the
    # iOS E2E harness signs in the dedicated test user this way
    # (AuthManager.signInWithPassword; no user-facing UI offers it).
    "ALLOW_USER_PASSWORD_AUTH",
  ]

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30

  prevent_user_existence_errors = "ENABLED"

  depends_on = [aws_cognito_identity_provider.apple]
}

# Domain for hosted UI (optional — used if you want Cognito's hosted sign-in page)
resource "aws_cognito_user_pool_domain" "mobile" {
  domain       = "${var.prefix}-mobile"
  user_pool_id = aws_cognito_user_pool.mobile.id
}
