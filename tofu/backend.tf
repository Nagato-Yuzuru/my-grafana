# Remote state on Cloudflare R2 (S3-compatible). Committed on purpose: what remains here is
# how this repo stores state (layout + S3-compat behaviour), not who owns the account. The S3
# endpoint embeds the Cloudflare account ID, so it is NOT hardcoded — it arrives as
# AWS_ENDPOINT_URL_S3, alongside AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY, via `op run`
# (tofu/op.env). This repo is public; the account ID stays out of it.
# State is still AES-GCM encrypted by the encryption{} block in versions.tf BEFORE upload —
# the passphrase stays in 1Password, so the object in R2 is ciphertext.
terraform {
  backend "s3" {
    bucket = "grafana-cloud-state"
    key    = "telemetry/terraform.tfstate" # object path; namespace other states beside it
    region = "auto"                        # R2 is region-less, but the S3 API requires a value

    # endpoints.s3 comes from AWS_ENDPOINT_URL_S3 (op.env → 1Password). Only `region` and
    # `endpoints.s3` have env-var equivalents; `bucket`/`key` would need -backend-config, and
    # a bare bucket name discloses nothing on its own, so it stays here.

    # R2 speaks S3 but isn't AWS: skip the AWS-only preflight calls, and skip the newer
    # request checksums R2 rejects. use_lockfile gives native locking (no DynamoDB); its
    # lock object honors skip_s3_checksum since OpenTofu PR #2606 (needs >= 1.11).
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true
    use_lockfile                = true
  }
}
