# Commands Reference

All `envctl` commands are prefixed with `envctl`.

## `envctl init`

Initialize a new `envctl` project in the current directory.

- **What it does**:
  1. Creates `.envctl.toml` from `.envctl.example.toml` if it exists, otherwise writes a minimal working config.
  2. Creates `.env.example` if it does not exist.
  3. Creates an empty `.envctl.lock` to anchor future version checks.
  4. Appends `envctl`-generated files (`.env`, `.envctl/`) to `.gitignore` if not already present.

- **Flag**:
  - `--config` (string): Config file to create (default: `.envctl.toml`).

---

## `envctl generate`

Generate everything in one pass: `.env` file, secrets, and certificates. This command runs the `envfile`, `secrets`, and `certs` phases in order.

- `--stage` (string): Target stage (e.g., `dev`, `staging`, `prod`).
- `--dry-run`: Show what would change without writing any files.
- `--quiet`: Suppress non-error output.
- `--config` (string): Path to the `.envctl.toml` configuration file.

```nushell
# First-time setup: generate everything at once
envctl generate --stage dev

# Preview what would be created
envctl generate --dry-run
```

---

## `envctl envfile`

### `envctl envfile generate`
Generates the `.env` file from the specified template and resolves tokens.

- `--stage` (string): Target stage.
- `--dry-run`: Preview changes without writing.
- `--quiet`: Suppress output.
- `--config` (string): Path to config file.

```nushell
# Generate .env for the dev stage (default)
envctl envfile generate

# Generate for a specific stage
envctl envfile generate --stage staging
envctl envfile generate --stage prod

# Preview without writing
envctl envfile generate --dry-run

# Switch the compose db variant without changing .envctl.toml
ENVCTL_VARIANTS="db.engine=postgres" envctl envfile generate --stage dev

# Select a non-default service for this run only
ENVCTL_SERVICES="db,cache" envctl envfile generate --stage dev
```

### `envctl envfile diff`
Shows the difference between the current `.env` file and what would be generated based on the configuration.

```nushell
envctl envfile diff
envctl envfile diff --stage prod
```

---

## `envctl secrets`

### `envctl secrets generate`
Generates any missing secrets defined in the configuration. Skips secrets that already exist on disk.

- `--stage` (string): Target stage.
- `--dry-run`: Preview changes without writing.

```nushell
# Generate all missing secrets (safe — skips existing)
envctl secrets generate

# Preview what would be created
envctl secrets generate --dry-run
```

### `envctl secrets rotate --key <NAME>`
Rotates a specific secret, generating a new value and updating all configured backends. Backs up the existing value before overwriting.

```nushell
envctl secrets rotate --key DB_PASSWORD_FILE
```

### `envctl secrets rotate-all`
Rotates all secrets defined in the configuration.

```nushell
envctl secrets rotate-all
envctl secrets rotate-all --dry-run
```

---

## `envctl certs`

### `envctl certs generate`
Generates any missing certificates in the PKI chain (Root CA → Intermediate → Leaf). Skips certs that already exist.

- `--name` (string): Generate only a specific certificate by its name.
- `--dry-run`: Preview changes without writing.

```nushell
# Generate the full chain
envctl certs generate

# Generate only a specific leaf cert
envctl certs generate --name leaf
```

### `envctl certs rotate --name <NAME>`
Rotates a specific certificate and any certificates below it in the chain. Backs up the existing cert before overwriting.

```nushell
envctl certs rotate --name leaf
```

### `envctl certs rotate-all`
Rotates the entire certificate chain starting from the Root CA.

```nushell
envctl certs rotate-all
```

### `envctl certs status`
Displays the current status and expiration dates of all managed certificates.

```nushell
envctl certs status
# NAME         STATUS    EXPIRES              DAYS LEFT
# root         OK        2027-03-01           700
# intermediate OK        2026-09-01           155
# leaf         WARNING   2026-04-28           30
```

---

## `envctl health`

Checks the health of your environment configuration and generated assets.

- `--profile` (string): Check only a specific profile (`envfile`, `secrets`, or `certs`).

```nushell
# Check everything
envctl health

# Check only secrets (e.g. before a deploy)
envctl health --profile secrets

# Check only cert expiry
envctl health --profile certs
```

---

## `envctl plugins`

### `envctl plugins list`
Lists all available and enabled plugins (providers and backends).

```nushell
envctl plugins list
# NAME      KIND      VERSION  STATUS
# git       provider  1.0.0    enabled
# password  provider  1.0.0    enabled
# compose   provider  1.0.0    enabled
# certs     provider  1.0.0    enabled
# file      backend   1.0.0    enabled
```

---

## `envctl version`

Prints the current version of `envctl`.

```nushell
envctl version
# 1.0.0
```
