# tofu runs under `op run`, so the bootstrap token, state passphrase, and stack slug come
# from tofu/op.env (1Password references + non-secrets). Interactive: biometric unlock.
# `tofu` and `op` must be on PATH.

# 1Password coordinates for the Alloy write token. Keep in sync with tofu variable
# onepassword_token_ref (= op://{{op_vault}}/{{op_item}}/{{op_field}}).
set shell := ["bash", "-euo", "pipefail", "-c"]

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

# launchd label + generated (gitignored, machine-specific) plist for the native run below.
[private]
_svc_label := "local.alloy"
[private]
_svc_plist := justfile_directory() / "alloy/alloy.launchd.plist"

# Run Alloy under launchd: supervised, Touch ID at launch, no auto-start next login
alloy-svc:
    #!/usr/bin/env bash
    set -euo pipefail
    # Bootstrapped from a non-registered path (not ~/Library/LaunchAgents) so it stays out
    # of login auto-start; KeepAlive restarts on crash only; re-run to reload after edits.
    repo="{{ justfile_directory() }}"
    op_bin="$(command -v op)"; alloy_bin="$(command -v alloy)"; uid="$(id -u)"
    [ -n "$op_bin" ]    || { echo "op not on PATH"; exit 1; }
    [ -n "$alloy_bin" ] || { echo "alloy not on PATH"; exit 1; }
    label="{{ _svc_label }}"; plist="{{ _svc_plist }}"
    cat > "$plist" <<EOF
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Label</key><string>${label}</string>
      <key>ProgramArguments</key>
      <array>
        <string>${op_bin}</string><string>run</string>
        <string>--env-file</string><string>${repo}/alloy/op.env</string>
        <string>--</string>
        <string>${alloy_bin}</string><string>run</string><string>${repo}/alloy/config.alloy</string>
      </array>
      <key>EnvironmentVariables</key>
      <dict><key>PATH</key><string>$(dirname "$op_bin"):$(dirname "$alloy_bin"):/usr/bin:/bin</string></dict>
      <key>WorkingDirectory</key><string>${repo}</string>
      <key>RunAtLoad</key><true/>
      <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
      <key>StandardOutPath</key><string>${repo}/alloy/alloy.log</string>
      <key>StandardErrorPath</key><string>${repo}/alloy/alloy.log</string>
    </dict>
    </plist>
    EOF
    # Reload cleanly: bootout any prior instance, wait until it's gone, then bootstrap.
    launchctl bootout "gui/${uid}/${label}" 2>/dev/null || true
    for _ in 1 2 3 4 5; do launchctl print "gui/${uid}/${label}" >/dev/null 2>&1 || break; sleep 0.3; done
    launchctl bootstrap "gui/${uid}" "$plist"
    echo "alloy loaded under launchd (${label}) — approve Touch ID at the prompt."
    echo "  status: just alloy-svc-status   logs: alloy/alloy.log   stop: just alloy-svc-stop"

# Stop + unload the launchd Alloy (bootout ignores KeepAlive, so it won't relaunch)
alloy-svc-stop:
    launchctl bootout "gui/$(id -u)/{{ _svc_label }}" && echo "alloy stopped" || echo "alloy not loaded"

# Show launchd state / pid for the Alloy service
alloy-svc-status:
    launchctl print "gui/$(id -u)/{{ _svc_label }}" 2>/dev/null | grep -E 'state = |pid = ' || echo "not loaded"

# Format alloy/config.alloy in place
alloy-fmt:
    alloy fmt -w alloy/config.alloy

# Validate config syntax + component wiring (no secrets needed — run before reloading)
alloy-validate:
    alloy validate alloy/config.alloy

# Hot-reload the running Alloy in place — no restart, no Touch ID (POST /-/reload)
alloy-reload:
    alloy validate alloy/config.alloy
    curl -fsS -X POST http://127.0.0.1:12345/-/reload && echo "reloaded" \
      || echo "reload failed — is alloy running? check alloy/alloy.log"

# Show tofu outputs (grafana_url, otlp_url, otlp_instance_id)
output:
    {{ _op }} {{ _tofu }} output

# gcx-bundled agent skills this project uses. The grafana/skills ones under
# .claude/skills/ are maintained by hand and intentionally NOT touched here.
gcx_skills := "create-dashboard explore-datasources"

# Refresh the gcx-bundled agent skills into .claude/skills/ (re-run after a gcx upgrade)
sync-skills:
    gcx agent skills install {{ gcx_skills }} --dir .claude --force

# Tear down the cloud policy/token
destroy:
    {{ _op }} {{ _tofu }} destroy
