# tofu runs under `op run`, so the bootstrap token, state passphrase, and stack slug come
# from tofu/op.env (1Password references + non-secrets). Interactive: biometric unlock.
# `tofu` and `op` must be on PATH.

# 1Password coordinates for the Alloy write token. Keep in sync with tofu variable
# onepassword_token_ref (= op://{{op_vault}}/{{op_item}}/{{op_field}}).
set shell := ["bash", "-euo", "pipefail"]

op_vault := "Homelab"
op_item := "Grafana Cloud Alloy"
op_field := "credential"

[private]
_tofu := "tofu -chdir=tofu"
[private]
_op := "op run --env-file tofu/op.env --"

# List available recipes
default:
    @just --list

# tofu init — download providers + set up state encryption (needs the passphrase)
init:
    {{ _op }} {{ _tofu }} init

# tofu fmt
fmt:
    {{ _tofu }} fmt

# tofu validate (encryption block needs the passphrase → runs under op run)
validate:
    {{ _op }} {{ _tofu }} validate

# tofu plan
plan:
    {{ _op }} {{ _tofu }} plan

# tofu apply — create policy/token (encrypted state), render alloy/op.env
apply:
    {{ _op }} {{ _tofu }} apply

# Push the current Alloy write token from tofu state into 1Password (creates the item if absent)
sync-token:
    token=$({{ _op }} {{ _tofu }} output -raw alloy_token)
    op item edit "{{ op_item }}" --vault "{{ op_vault }}" "{{ op_field }}[password]=${token}" \
      || op item create --category "API Credential" --title "{{ op_item }}" --vault "{{ op_vault }}" "{{ op_field }}[password]=${token}"

# Rotate the write token and re-sync it to 1Password
rotate:
    {{ _op }} {{ _tofu }} apply -replace=grafana_cloud_access_policy_token.alloy -auto-approve
    just sync-token

# Run Alloy against the rendered config (token resolved from 1Password via op run)
alloy:
    op run --env-file alloy/op.env -- alloy run alloy/config.alloy

# Show tofu outputs (grafana_url, otlp_url, otlp_instance_id)
output:
    {{ _op }} {{ _tofu }} output

# Tear down the cloud policy/token
destroy:
    {{ _op }} {{ _tofu }} destroy
