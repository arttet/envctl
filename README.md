# envctl

A Nushell-native configuration compiler and execution engine for environment and secrets management.

## What it does

- Generates `.env` from declarative templates with `{{ token }}` substitution
- Manages secrets — generates, rotates, and delivers them to file or other backends
- Manages PKI certificate chains (Root CA → Intermediate → Leaf) via openssl
- Validates all config against TOML schemas before writing anything
- Tracks versions in `.envctl.lock` (commit this) and an audit log in `.envctl/state.ndjson` (gitignore the `.envctl/` directory)

## Requirements

- [Nushell](https://www.nushell.sh/) >= 0.94
- `openssl` >= 3.0 (for secrets and certificates)
- `git` (for the `git` provider)

## Install globally

```nushell
# Install to default directory and register autoload hook
nu install.nu

# Or via just
just install

# Custom install directory
nu install.nu --prefix ~/.envctl

# See what would be installed without writing anything
nu install.nu --dry-run

# Uninstall
nu install.nu --uninstall
```

After installation, restart your Nushell session — all `envctl` commands are available globally.

**Default install paths:**

| OS | Path |
|---|---|
| Linux / macOS | `~/.local/share/envctl` |
| Windows | `%LOCALAPPDATA%\envctl` |

The installer also writes an autoload hook to `$nu.vendor-autoload-dirs`, so no manual `source` is needed.

## Quick start (without global install)

```nushell
# 1. Initialize project (creates .envctl.toml and setup gitignore)
nu envctl.nu envctl init

# 2. Generate .env from .env.example
nu envctl.nu envctl envfile generate
```
# 3. Generate all missing secrets
nu envctl.nu envctl secrets generate

# 4. Generate PKI certificates (if [certs] is configured)
nu envctl.nu envctl certs generate

# 5. Check health
nu envctl.nu envctl health
```

## Install as autoload hook

```nushell
just reload
```

After this, all `envctl` commands are available directly in your shell without `nu envctl.nu`.

## Config format

Create `.envctl.toml` in your project root:

```toml
schema = "v1"

[providers]
enabled = ["git", "password"]

[generators]
GIT_ROOT_DIR = "{{ provider:git.top-level-dir }}"

[envfile]
file    = ".env"
pattern = ".env.example"

[secrets]
base_dir = "."

[secrets.DB_PASSWORD_FILE]
value_source = "{{ provider:password.generate-password }}"
targets      = ["file"]

[secrets.DB_PASSWORD_FILE.options.file]
path = "{{ GIT_ROOT_DIR }}/secrets/db_password"
```

Then commit `.envctl.toml` and `.envctl.lock`. Add `.envctl/` and `.env` to `.gitignore`.

## Token grammar

| Token | Example | Resolves to |
|---|---|---|
| `{{ IDENT }}` | `{{ GIT_ROOT_DIR }}` | Value from resolved generators |
| `{{ secret:IDENT }}` | `{{ secret:DB_PASS_FILE }}` | Contents of file at path stored in IDENT |
| `{{ provider:NAME.FN }}` | `{{ provider:git.top-level-dir }}` | Calls fn from provider manifest |

## Commands

```
envctl envfile generate [--stage] [--dry-run] [--quiet] [--config]
envctl envfile diff

envctl secrets generate [--stage] [--dry-run]
envctl secrets rotate   --key NAME
envctl secrets rotate-all

envctl certs generate  [--name NAME] [--dry-run]
envctl certs rotate    --name NAME
envctl certs rotate-all
envctl certs status

envctl health [--profile envfile|secrets|certs]
envctl plugins list
```

## Profiles

| Profile | What runs |
|---|---|
| `envfile` | Parse generators + render `.env` |
| `secrets` | Generate missing secrets via providers, write via backends |
| `certs` | Generate PKI certificate chains |
| `all` | envfile + secrets + certs |

## Built-in providers

| Provider | Token | Config |
|---|---|---|
| `git` | `{{ provider:git.top-level-dir }}` | none (override with `ENVCTL_GIT_ROOT`) |
| `password` | `{{ provider:password.generate-password }}` | `length`, `charset`, `tool` |
| `compose` | `{{ provider:compose.collect-files }}` | `base_dir`, `base_files`, `services` |
| `certs` | (used internally by `envctl certs`) | `tool`, `key_bits`, `organization`, `country` |

## Built-in backends

| Backend | Writes to |
|---|---|
| `file` | Local filesystem path |

## Environment variables

| Variable | Default | Effect |
|---|---|---|
| `ENVCTL_CONFIG` | `.envctl.toml` | Override config path |
| `ENVCTL_STAGE` | `dev` | Override stage |
| `ENVCTL_DRY_RUN` | `false` | Enable dry-run (no writes) |
| `ENVCTL_QUIET` | `false` | Suppress non-error output |

## Development

```nushell
just deps    # Install nufmt + nu-lint
just fmt     # Format code
just lint    # Run linter
just test    # Run tests
just run envctl health  # Run any command
```

## Running tests

```nushell
nu run_tests.nu           # All tests
nu run_tests.nu --unit    # Unit tests only
nu run_tests.nu --file tests/unit/grammar_test.nu
```

## Architecture

See [AGENTS.md](AGENTS.md) for the full architectural specification, layer responsibilities, plugin manifest contract, and Nushell style guide.

## License

Apache 2.0 — see [LICENSE](LICENSE).
