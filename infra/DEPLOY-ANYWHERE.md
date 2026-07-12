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

## 4. Terraform state — the one thing that must be shared

### Today: local state, copied between machines
The backend is the **default local** one (no `backend` block), so state lives in
`infra/terraform.tfstate` and is **gitignored**. To work on a new machine you must
bring the current state with you:

```bash
# On the machine that has the good state, package it:
tar -czf terraform-state-backup.tar.gz -C infra \
    terraform.tfstate terraform.tfstate.backup terraform.tfvars

# On the new machine, drop the files into infra/ and:
cd infra && terraform init -input=false
terraform plan            # must show 0 to add / 0 to destroy (only expected drift)
```

A healthy `plan` after restoring state shows **0 to add, 0 to destroy** — at most a
few in-place Lambda `source_code_hash` updates (that just means `infra/src` here
differs from what's currently deployed; applying redeploys the current code).

⚠️ **Never** `terraform apply` with EMPTY state — it will try to re-create the ~98
already-existing resources and collide with the live stack.

### Recommended: migrate state to an S3 remote backend (do this once)
This removes the "ship the tfstate around" step forever — every machine then just runs
`terraform init` and shares one locked, versioned state. Terraform 1.15+ supports S3
**native** locking (`use_lockfile`), so no DynamoDB lock table is needed.

1. Create a versioned, encrypted, private state bucket (one-time):
   ```bash
   aws s3api create-bucket --bucket giftmaxxing-tfstate-445056752928 --region us-east-1
   aws s3api put-bucket-versioning --bucket giftmaxxing-tfstate-445056752928 \
       --versioning-configuration Status=Enabled
   aws s3api put-bucket-encryption --bucket giftmaxxing-tfstate-445056752928 \
       --server-side-encryption-configuration \
       '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"aws:kms"}}]}'
   aws s3api put-public-access-block --bucket giftmaxxing-tfstate-445056752928 \
       --public-access-block-configuration \
       BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
   ```
2. Add a backend block to `infra/versions.tf` (inside the existing `terraform {}`):
   ```hcl
   backend "s3" {
     bucket       = "giftmaxxing-tfstate-445056752928"
     key          = "infra/dev/terraform.tfstate"
     region       = "us-east-1"
     encrypt      = true
     use_lockfile = true   # S3-native state locking (TF >= 1.10)
   }
   ```
3. Migrate the existing local state up (run from the machine that HAS the good state):
   ```bash
   cd infra && terraform init -migrate-state   # answer "yes" to copy state to S3
   ```
4. From then on, on ANY machine: `terraform init` (pulls remote state) → `plan` / `apply`.
   You still need `terraform.tfvars` locally (§3); only the tfstate moves to S3.

> This is a real infra change (adds a backend + an S3 bucket). It's safe, but coordinate
> so nobody is mid-apply during the migration.

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
