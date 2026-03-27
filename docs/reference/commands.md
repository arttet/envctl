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

---

## `envctl envfile`

### `envctl envfile generate`
Generates the `.env` file from the specified template and resolves tokens.

- `--stage` (string): Target stage.
- `--dry-run`: Preview changes without writing.
- `--quiet`: Suppress output.
- `--config` (string): Path to config file.

### `envctl envfile diff`
Shows the difference between the current `.env` file and what would be generated based on the configuration.

---

## `envctl secrets`

### `envctl secrets generate`
Generates any missing secrets defined in the configuration.

- `--stage` (string): Target stage.
- `--dry-run`: Preview changes without writing.

### `envctl secrets rotate --key <NAME>`
Rotates a specific secret, generating a new value and updating all configured backends.

### `envctl secrets rotate-all`
Rotates all secrets defined in the configuration.

---

## `envctl certs`

### `envctl certs generate`
Generates any missing certificates in the PKI chain.

- `--name` (string): Generate only a specific certificate by its name.
- `--dry-run`: Preview changes without writing.

### `envctl certs rotate --name <NAME>`
Rotates a specific certificate and any certificates below it in the chain.

### `envctl certs rotate-all`
Rotates the entire certificate chain starting from the Root CA.

### `envctl certs status`
Displays the current status and expiration dates of all managed certificates.

---

## `envctl health`

Checks the health of your environment configuration and generated assets.

- `--profile` (string): Check only a specific profile (`envfile`, `secrets`, or `certs`).

---

## `envctl plugins`

### `envctl plugins list`
Lists all available and enabled plugins (providers and backends).
