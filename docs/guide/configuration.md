# Configuration

The behavior of `envctl` is defined in a `.envctl.toml` file in your project root.

## Basic Structure

```toml
schema = "v1"

[providers]
enabled = ["git", "password", "compose"]

[generators]
# Tokens that resolve into simple strings
GIT_ROOT_DIR = "{{ provider:git.top-level-dir }}"

[envfile]
file    = ".env"
pattern = ".env.example"

[secrets]
base_dir = "secrets"

[secrets.DB_PASSWORD_FILE]
value_source = "{{ provider:password.generate-password }}"
targets      = ["file"]
options.file.path = "{{ GIT_ROOT_DIR }}/secrets/db_password"

[certs]
base_dir = "certs"
# Certificate chain configuration
```

## Section Details

### `schema`
Specifies the configuration version. Currently, only `"v1"` is supported.

### `providers`
Configures external data sources and generation functions.
- `enabled`: List of provider names to activate.

### `generators`
Defines project-level variables that can be used as tokens in other parts of the configuration.
- Use <span v-pre>`{{ provider:NAME.FN }}`</span> to call a provider function.

### `envfile`
Settings for generating the main environment file.
- `file`: Path to the output `.env` file.
- `pattern`: Path to the template or example file to read.

### `secrets`
Defines how secrets are generated and where they are stored.
- `base_dir`: Default directory for secret files.
- `[secrets.NAME]`: Individual secret configuration.
  - `value_source`: A token or expression that provides the secret's value.
  - `targets`: List of backends to write the secret to (e.g., `["file"]`).
  - `options`: Backend-specific settings.

### `certs` (Optional)
Configuration for PKI certificate chains. This includes Root CA, Intermediate CA, and Leaf certificates.

## Profiles

You can group configurations and control their execution via [Profiles](./profiles).
