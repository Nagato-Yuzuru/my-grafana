# Claude Code → Alloy → Grafana Cloud telemetry

Declarative (OpenTofu) telemetry pipeline for Claude Code. tofu state lives in Cloudflare
R2 (encrypted), so any of your Macs can share it; Alloy still runs locally per machine.

```
Claude Code ──OTLP(grpc :4317)──▶ local Alloy ──OTLP/HTTP + Basic auth──▶ Grafana Cloud
 (.claude/settings.json env)      (op run + config.alloy)                 Mimir / Loki / Tempo
```

## Secret model — nothing in plaintext on disk

- The Grafana Cloud **write token** lives only in **1Password**. Alloy reads it via
  `op run`, which injects it into the process environment at launch (biometric unlock) —
  never a file.
- **tofu state is encrypted** (OpenTofu native AES-GCM) *before* it leaves the machine, then
  stored in **Cloudflare R2**; the passphrase comes from 1Password via `op run`, so the object
  in the bucket is ciphertext, not plaintext. The R2 access keys ride the same `op run` — never
  on disk.
- **Committed files carry no secrets**: `tofu/op.env` holds `op://` *references*;
  `alloy/config.alloy` reads everything from the environment.
- Interactive by design: you unlock 1Password (Touch ID) when you start tofu or Alloy.

## Layout

| Path | What |
|---|---|
| `tofu/` | policy + write token; renders `alloy/op.env`. Remote state on R2 (encrypted) |
| `tofu/op.env` | **committed**: `op://` refs for tofu's secrets, stack slug + R2 keys/endpoint (no secrets) |
| `tofu/backend.tf` | **committed**: R2 remote-state backend — state layout + S3-compat flags; no account identity |
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
   - **`Cloudflare R2 tofu state`** → the R2 **S3 API token**: field `AK` = Access Key ID,
     field `SK` = Secret Access Key (both concealed), plus field `S3URL` = the account-level
     S3 endpoint. You mint the token and read the endpoint off the dashboard in step 2.
   - `Grafana Cloud Alloy` is created for you by `just sync-token`.

2. **Cloudflare R2 bucket** (holds the remote state). With `wrangler` logged in:
   ```bash
   wrangler r2 bucket create grafana-cloud-state
   ```
   Then Cloudflare dashboard → R2 → *Manage R2 API Tokens* → create a token with **Object
   Read & Write** scoped to that bucket (wrangler can't mint S3 tokens). Store the resulting
   Access Key ID / Secret Access Key in the `Cloudflare R2 tofu state` item (`AK` / `SK`), and
   the **account-level** S3 endpoint `https://<account-id>.r2.cloudflarestorage.com` in the
   same item's `S3URL` field. The dashboard's per-bucket *S3 API* value ends in `/<bucket>` —
   drop that suffix, since `use_path_style` appends the bucket itself.

   The endpoint lives in 1Password rather than `tofu/backend.tf` because it embeds the
   Cloudflare account ID and this repo is public. The bucket name stays in `backend.tf`
   (adjust it there if yours differs): the s3 backend has no env var for `bucket`, and a
   bucket name is not a credential — without the account it identifies nothing.

3. **`tofu/op.env`** already points at those items — every value is an `op://` ref (bootstrap
   token, state passphrase, stack slug, the R2 `AK`/`SK` and endpoint), no literals. Adjust the
   vault/item names there if yours differ, and keep the Justfile's `op_vault`/`op_item`/
   `op_field` and the tofu variable `onepassword_token_ref` in sync.

4. **Tools** — install `tofu`, Grafana `alloy` (per platform — see [Run Alloy](#run-alloy)),
   and the **1Password CLI** with desktop-app integration enabled (1Password →
   Settings → Developer → *Integrate with 1Password CLI*).

## Bring-up

First machine — migrate the existing encrypted local state up to R2 once (answer `yes` at
the prompt), then the usual flow:

```bash
op run --env-file tofu/op.env -- \
  tofu -chdir=tofu init -migrate-state   # one-time: local state → R2 backend
just apply         # creates policy+token if absent, renders alloy/op.env
just sync-token    # push the write token into 1Password
```

Any **additional machine** — state is shared from R2, so nothing is recreated:

```bash
just init          # connects to the R2 backend, pulls the shared state
just apply         # policy/token already in state → just renders this machine's alloy/op.env
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
