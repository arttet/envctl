---
name: envctl
description: Run envctl commands for this project — generate .env, secrets, certs, or everything at once. Use this whenever the environment needs to be initialized, regenerated, or inspected. Supports all envctl profiles (envfile, secrets, certs, all) and stages (dev, staging, prod).
argument-hint: [generate|envfile generate|secrets generate|certs generate|health] [--stage dev|staging|prod] [--dry-run]
allowed-tools: Bash, Read, Glob
---

# envctl — environment and secrets management

envctl uses a **two-phase model**: compile (pure, no side effects) then execute (writes files). Errors in the compile phase are surfaced before anything is written.

## Architecture context (from AGENTS.md)

**Profiles:**

| Profile | What it generates |
|---|---|
| `envfile` | `.env` file only — resolves generators + provider tokens |
| `secrets` | Secret files only — runs `value_source` providers, writes backends |
| `certs`   | PKI certificate chain only — Root CA → Intermediate → Leaf |
| `all`     | `.env` + secrets + certs in one pass |

**Token grammar** (used in `.env.example` and `.envctl.toml`):

| Token | Example | Resolves to |
|---|---|---|
| `{{ IDENT }}` | `{{ GIT_ROOT_DIR }}` | Value from `[generators]` or a previously resolved line |
| `{{ provider:NAME.FN }}` | `{{ provider:compose.collect-files }}` | Return value of provider function |
| `{{ secret:IDENT }}` | `{{ secret:DB_PASS_FILE }}` | Contents of the file at the path stored in `IDENT` |

**Config file:** `.envctl.toml` (always this name — never `.envctl` alone).

## Steps

1. Check that `.envctl.toml` exists in the current directory. If it does not, suggest `envctl init`.

2. Run the requested command. If the user did not specify one, run:
   ```
   envctl envfile generate $ARGUMENTS
   ```

3. **On success:**
   - For `envfile generate`: read the generated `.env` and confirm no unresolved `{{ }}` tokens remain. Report stage and variable count.
   - For `secrets generate`: report which secrets were written vs skipped (already existed).
   - For `certs generate`: report which certs were created.
   - For `generate` (all): summarise all three phases.

4. **On failure — diagnose by error type:**
   - **Unresolved token** — show the token and check: (a) the provider is in `[providers].enabled`, (b) the generator key exists in `[generators]`, (c) for `{{ secret:X }}`, the secret file must exist on disk — run `envctl secrets generate` first.
   - **Lock version mismatch** — a provider's manifest version changed since the lock was written. Run `envctl generate` once to update `.envctl.lock`.
   - **Schema validation error** — `.envctl.toml` has an invalid key or wrong type. Show the offending field and the expected type from the error.
   - **Provider not enabled** — a `provider:` token references a provider not listed in `[providers].enabled`. Show the fix.
   - **Path traversal** — a secret path escapes `secrets.base_dir`. Show the resolved path and the base_dir.

## Common commands

```nushell
# First-time setup
envctl init
envctl generate --stage dev          # writes .env + secrets + certs

# Regenerate .env only
envctl envfile generate --stage dev
envctl envfile generate --stage prod
envctl envfile generate --dry-run    # preview without writing

# Secrets
envctl secrets generate              # create missing secrets (skips existing)
envctl secrets rotate --key NAME     # rotate one secret (backs up old value)
envctl secrets rotate-all

# Certs
envctl certs generate
envctl certs status                  # show expiry dates
envctl certs rotate --name leaf

# Health check
envctl health
envctl health --profile secrets

# Plugins
envctl plugins list
```

## Environment variable overrides

| Variable | Effect |
|---|---|
| `ENVCTL_STAGE` | Override `--stage` |
| `ENVCTL_DRY_RUN` | Enable dry-run without the flag |
| `ENVCTL_QUIET` | Suppress non-error output |
| `ENVCTL_CONFIG` | Use a different config file path |
| `ENVCTL_SERVICES` | Override selected compose services (e.g. `"db,cache"`) |
| `ENVCTL_VARIANTS` | Override compose variant (e.g. `"db.engine=postgres"`) |

## Notes

- `envctl generate` (profile `all`) is the recommended first-run command — it generates everything in the correct order.
- For `{{ secret:IDENT }}` tokens in `.env.example`, secrets must be on disk before `envfile generate` runs.
- The compose provider builds `COMPOSE_FILE` by collecting files that **actually exist on disk** for the given stage and selected services. If `COMPOSE_FILE` is missing a file, check that the file exists at the expected path.
- Lock file (`.envctl.lock`) must be committed to git. State file (`.envctl.state.ndjson`) is local-only — add to `.gitignore`.
