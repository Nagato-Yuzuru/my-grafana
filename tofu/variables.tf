variable "grafana_cloud_access_policy_token" {
  type        = string
  sensitive   = true
  description = <<-EOT
    Bootstrap Grafana Cloud Access Policy token: lets OpenTofu read the stack and manage
    the Alloy write policy. Realm: org. Required scopes:
      stacks:read, accesspolicies:read, accesspolicies:write, accesspolicies:delete
    Injected as TF_VAR_grafana_cloud_access_policy_token; `op run` (see tofu/op.env)
    resolves it from 1Password so it never lands on disk.
  EOT
}

variable "stack_slug" {
  type        = string
  description = "Grafana Cloud stack slug — the subdomain in https://<slug>.grafana.net."
}

variable "state_passphrase" {
  type        = string
  sensitive   = true
  description = <<-EOT
    Passphrase for OpenTofu native state/plan encryption (must be >= 16 chars).
    Injected as TF_VAR_state_passphrase; `op run` resolves it from 1Password.
    If lost, the encrypted state is unreadable — re-apply mints a fresh policy/token.
  EOT
}

variable "onepassword_token_ref" {
  type        = string
  default     = "op://Homelab/Grafana Cloud Alloy/credential"
  description = <<-EOT
    1Password secret reference where `just sync-token` stores the Alloy write token.
    Written verbatim into alloy/op.env for `op run` to resolve at Alloy launch.
    The Justfile (op_vault/op_item/op_field) is authoritative — keep this default in sync.
  EOT
}
