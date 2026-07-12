# Deploy Giftmaxxing infra from anywhere (cloud VM or local Mac)

A portable runbook so you can run `terraform plan` / `apply` for `infra/` from any
machine — a Cursor cloud VM, your Mac, CI, whatever. The **only** thing that must
travel between machines is the Terraform **state** and your **secrets** (`terraform.tfvars`).
Everything else is reproducible from this repo.

> TL;DR: install the toolchain → authenticate to AWS (SSO) → make Terraform state
> available (today it's a local file you copy around; **recommended:** migrate it to an
> S3 remote backend once, then every machine just `terraform init`).

---

## 1. Toolchain (install once per machine / VM image)

| Tool | Version | Why |
|---|---|---|
| **Node.js** | 22.x | Bundles the Lambda source in `infra/src` (and runs `infra/ingest`). |
| **AWS CLI** | v2 | Auth (SSO) + resource inspection. |
| **Terraform** | **>= 1.15.6** | The current state was written by **1.15.6**; older Terraform will REFUSE to read it. `versions.tf` only pins `>= 1.6`, but the state file forces `>= 1.15.6`. |

Install (Linux x86_64 — this is what the cloud VM uses):

```bash
# AWS CLI v2
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
cd /tmp && unzip -q -o awscliv2.zip && sudo ./aws/install --update

# Terraform 1.15.6
curl -fsSL "https://releases.hashicorp.com/terraform/1.15.6/terraform_1.15.6_linux_amd64.zip" -o /tmp/tf.zip
cd /tmp && unzip -q -o tf.zip && sudo install -m 0755 terraform /usr/local/bin/terraform
```

On a **Mac**, use Homebrew instead: `brew install awscli` and
`brew install terraform` (or `tfenv` pinned to `1.15.6`). Node via `nvm use 22`.

> These are **system tools**, not repo deps — they are intentionally NOT in the Cursor
> update script. On a fresh cloud VM without them, reinstall with the commands above.

---

## 2. Authenticate to AWS (SSO — preferred)

Account `445056752928`, region `us-east-1`.

```bash
aws configure sso              # one-time: SSO start URL + region, pick the account
                               # + an admin-capable role, name the profile e.g.
                               # giftmaxxing_dev_cursor_cloud
aws sso login --profile giftmaxxing_dev_cursor_cloud
export AWS_PROFILE=giftmaxxing_dev_cursor_cloud
export AWS_REGION=us-east-1
aws sts get-caller-identity    # confirm the assumed role
```

Headless VMs print a verification URL + code — open them in a browser on any device.
SSO sessions are short-lived; re-run `aws sso login` when `get-caller-identity` starts
failing. (Alternative: paste temporary keys into repo-root `.env` and
`set -a; source ../.env; set +a` — SSO is cleaner.)

---

## 3. Secrets — `terraform.tfvars` (gitignored)

Several inputs (alert emails, `admin_api_secret`, `session_jwt_secret`, Apple/APNs
keys, …) live in `infra/terraform.tfvars`, which is **gitignored** (`example.tfvars`
is the template). Without it, `apply` would blank those values out. Keep a copy in a
password manager / secrets vault and drop it into `infra/terraform.tfvars` on each
machine. Confirm it's present before applying:

```bash
test -f infra/terraform.tfvars && echo "tfvars OK" || echo "MISSING tfvars"
```

---

## 4. Terraform state — now on S3 (shared, no copying)

State lives in an **S3 remote backend** (configured in `versions.tf`), so every machine
just runs `terraform init` and shares one locked, versioned state — no more shipping
`terraform.tfstate` around. Terraform 1.15's S3-native locking (`use_lockfile`) is used,
so there is **no DynamoDB lock table**.

- **Bucket:** `giftmaxxing-tfstate-445056752928` (us-east-1) — versioned, SSE-S3
  (AES256, bucket keys), public access fully blocked. Tagged `Project=giftmaxxing`.
- **State key:** `infra/dev/terraform.tfstate`.

```hcl
# infra/versions.tf (already committed)
backend "s3" {
  bucket       = "giftmaxxing-tfstate-445056752928"
  key          = "infra/dev/terraform.tfstate"
  region       = "us-east-1"
  encrypt      = true
  use_lockfile = true   # S3-native locking (TF >= 1.10)
}
```

On any machine:

```bash
cd infra
terraform init      # pulls the shared remote state from S3
terraform plan      # healthy = 0 to add / 0 to destroy (a few in-place Lambda
                    # source_code_hash updates are expected: infra/src here just
                    # differs from what's deployed; apply redeploys current code)
```

You still need `terraform.tfvars` locally (§3) — only the tfstate is shared via S3.

> ⚠️ If `plan` ever wants to CREATE the ~98 existing resources, your backend/state is
> misconfigured (e.g. `terraform init` didn't pick up the S3 backend, or you're pointed
> at an empty state). Fix that before applying — never apply against empty state.

### How the bucket was bootstrapped (reference — already done)
The state bucket can't live in the same state it stores (chicken-and-egg), so it was
created once out-of-band with the AWS CLI:

```bash
B=giftmaxxing-tfstate-445056752928
aws s3api create-bucket --bucket "$B" --region us-east-1
aws s3api put-bucket-versioning --bucket "$B" --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$B" --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'
aws s3api put-public-access-block --bucket "$B" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

Then the pre-existing local state was migrated up once with
`terraform init -migrate-state`. You should not need to repeat this.

---

## 5. Plan / apply workflow

```bash
cd infra
export AWS_PROFILE=giftmaxxing_dev_cursor_cloud AWS_REGION=us-east-1

# Lambda code is bundled from src/ — install its runtime deps first (needs
# @aws-sdk/client-s3vectors, which is NOT in the nodejs20.x runtime SDK):
npm --prefix src ci

terraform plan -out tfplan     # review: expect 0 add / 0 destroy on a no-op change
terraform apply tfplan         # only after the plan looks right
terraform output -raw cloudfront_api_url   # the public API base for web/
```

- `web/` reads the API via `NEXT_PUBLIC_API_URL` (prefer the CloudFront URL). It is NOT
  deployed by Terraform — `web/` auto-deploys to Vercel on push to `main`.
- Full resource/route reference and the cost runbook are in `infra/README.md`.
