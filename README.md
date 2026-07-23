# Claude Code → Alloy → Grafana Cloud telemetry

Declarative (OpenTofu) telemetry pipeline for Claude Code, running on a single laptop.

```
Claude Code ──OTLP(grpc :4317)──▶ local Alloy ──OTLP/HTTP + Basic auth──▶ Grafana Cloud
 (.claude/settings.json env)      (op run + config.alloy)                 Mimir / Loki / Tempo
```

## Secret model — nothing in plaintext on disk

- The Grafana Cloud **write token** lives only in **1Password**. Alloy reads it via
  `op run`, which injects it into the process environment at launch (biometric unlock) —
  never a file.
- **tofu state is encrypted** (OpenTofu native AES-GCM); its passphrase also comes from
  1Password via `op run`. So the token-in-state is ciphertext, not plaintext.
- **Committed files carry no secrets**: `tofu/op.env` holds `op://` *references*;
  `alloy/config.alloy` reads everything from the environment.
- Interactive by design: you unlock 1Password (Touch ID) when you start tofu or Alloy.

## Layout

| Path | What |
|---|---|
| `tofu/` | policy + write token (encrypted state); renders `alloy/op.env` |
| `tofu/op.env` | **committed**: `op://` refs for tofu's secrets + your stack slug (no secrets) |
| `alloy/config.alloy` | **committed**, static Alloy config; reads coordinates via `sys.env` |
| `alloy/op.env` | **generated** by `tofu apply` (non-secret: endpoint, instance id, token ref) |
| `claude/settings.telemetry.json` | `env` block to merge into your Claude Code settings |
| `Justfile` | `init` / `apply` / `sync-token` / `rotate` / `alloy` / `output` / `destroy` |

`mise.toml` pins OpenTofu + just + prek for [mise](https://mise.jdx.dev) users, but nothing
requires mise — any `tofu`, `op`, and (per platform) `alloy` on `PATH` work.

## Repo checks

`just setup` (once) installs the pinned tools and wires [prek](https://github.com/j178/prek)
into `.git/hooks`; after that every commit runs `.pre-commit-config.yaml` — hygiene checks,
`tofu fmt`, `alloy fmt`/`validate`, `just --fmt`, and a gitleaks scan guarding the
no-plaintext-secrets model. `just check` runs the same set against the whole tree; CI
(`.github/workflows/ci.yaml`) repeats it on push/PR plus a full-history gitleaks pass.
Anything needing `op run` (tofu init/validate/plan) stays local and manual by design.

## Signal scope (current: full capture)

`claude/settings.telemetry.json` turns on the full firehose — 8 metrics, ~30 event
types, and beta traces — **including content gates** (`OTEL_LOG_USER_PROMPTS`,
`OTEL_LOG_ASSISTANT_RESPONSES`, `OTEL_LOG_TOOL_DETAILS`, `OTEL_LOG_TOOL_CONTENT`).
Prompt/response/tool text is exported to Grafana Cloud. Single-user, so it stays in the
free tier with no third-party leak beyond your own stack. For metadata only (lengths,
tokens, cost — no text), drop the four `OTEL_LOG_*` keys. Left off: `OTEL_LOG_RAW_API_BODIES`.

## One-time setup

1. **1Password items** (vault `Homelab`):
   - **`Grafana Cloud Bootstrap`** → field `credential` = a Cloud Access Policy token
     (realm: org; scopes `stacks:read` + `accesspolicies:read`/`write`/`delete`).
     Create it in the Grafana Cloud portal → Access Policies.
   - **`Grafana Cloud tofu state`** → field `password` = a strong passphrase (≥ 16 chars;
     let 1Password generate it — losing it makes the encrypted state unreadable), and
     field `username` = your stack slug.
   - `Grafana Cloud Alloy` is created for you by `just sync-token`.

2. **`tofu/op.env`** already points at those items — all three values are `op://` refs
   (bootstrap token, state passphrase, and the stack slug), no literals. Adjust the
   vault/item names there if yours differ, and keep the Justfile's `op_vault`/`op_item`/
   `op_field` and the tofu variable `onepassword_token_ref` in sync.

3. **Tools** — install `tofu`, Grafana `alloy` (per platform — see [Run Alloy](#run-alloy)),
   and the **1Password CLI** with desktop-app integration enabled (1Password →
   Settings → Developer → *Integrate with 1Password CLI*).

## Bring-up

```bash
just init          # Touch ID; download providers + set up state encryption
just apply         # creates policy+token (encrypted state), renders alloy/op.env
just sync-token    # push the write token into 1Password
```

Then **wire Claude Code** — merge `claude/settings.telemetry.json` into your user settings
so telemetry applies to every session:

```bash
jq -s '.[0] * .[1]' ~/.claude/settings.json claude/settings.telemetry.json > /tmp/s.json \
  && mv /tmp/s.json ~/.claude/settings.json
```

## Run Alloy

`op run` injects the token from 1Password at launch — nothing on disk:

```bash
just alloy         # foreground: op run --env-file alloy/op.env -- alloy run alloy/config.alloy
```

Want it supervised and out of the way? `just alloy-svc` loads the same `op run … alloy run`
command as a **launchd** agent in your GUI session: Touch ID at launch, `KeepAlive` restarts
it if it crashes, and it's bootstrapped from a non-registered path (`alloy/alloy.launchd.plist`,
generated + gitignored) so it does **not** auto-start next login. It runs until
`just alloy-svc-stop` or logout/shutdown; check `just alloy-svc-status`, tail `alloy/alloy.log`.
Because every (re)launch runs `op run`, each start needs a Touch ID approval — that's the cost
of keeping the token off disk. If it doesn't prompt or dies immediately, unlock 1Password (or
run `just alloy` once in the foreground to confirm auth), then retry.

Install differs per platform:

- **macOS (Homebrew):** `brew install grafana/grafana/alloy` (confirm the formula name).
- **Linux / other:** package manager or release binary; see
  <https://grafana.com/docs/alloy/latest/set-up/install/>.

Running Alloy under a boot-time service manager (brew services / systemd) would need a
1Password **service account** token available unattended — out of scope for the
interactive/at-work model here (a *boot-time* daemon can't do the Touch ID unlock). The
launchd agent above is the supervised middle ground: it lives in your logged-in GUI session,
still gated by Touch ID. Start `just alloy` (or `just alloy-svc`) when you begin work.

## Rotate the token

```bash
just rotate        # tofu apply -replace on the token, then re-sync to 1Password
```

## Verify

In Grafana → Explore: query `claude_code_session_count` (Prometheus) and
`{service_name="claude-code"}` (Loki). `just output` prints `grafana_url` / `otlp_url`.
