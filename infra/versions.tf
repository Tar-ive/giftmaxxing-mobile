terraform {
  # State was migrated to S3 by Terraform 1.15.6; the state format requires
  # Terraform >= 1.15.6 to read it (older versions will refuse). The S3 native
  # lock (`use_lockfile`) also needs >= 1.10.
  required_version = ">= 1.15.6"

  # Remote state on S3 (versioned + SSE-S3, public access blocked), with S3-native
  # locking (no DynamoDB lock table). Bootstrapped out-of-band via the AWS CLI; see
  # DEPLOY-ANYWHERE.md. Backend config must be literal (no variables/interpolation).
  backend "s3" {
    bucket       = "giftmaxxing-tfstate-445056752928"
    key          = "infra/dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}
