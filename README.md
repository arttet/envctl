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

## Install

```nushell
http get https://raw.githubusercontent.com/arttet/envctl/main/install.nu | into string | nu -c $in
```

After installation, restart your Nushell session — all `envctl` commands are available globally.

**Default install paths:**

| OS            | Path                    |
|---------------|-------------------------|
| Linux / macOS | `~/.local/share/envctl` |
| Windows       | `%LOCALAPPDATA%\envctl` |

The installer writes an autoload hook to `$nu.vendor-autoload-dirs` — no manual `source` needed.

**More options** (from a cloned repo):

```nushell
nu install.nu --prefix ~/.envctl  # custom install directory
nu install.nu --dry-run           # preview without writing anything
nu install.nu --uninstall         # remove files and autoload hook
```

## Quick start

### Initialize project (creates .envctl.toml and setup gitignore)

```nushell
envctl init
```

### Generate .env from .env.example

```nushell
envctl envfile generate
```

### Generate all missing secrets

```nushell
envctl secrets generate
```

### Generate PKI certificates (if [certs] is configured)

```nushell
envctl certs generate
```

### Check health

```nushell
envctl health
```

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

| Token                    | Example                            | Resolves to                              |
|--------------------------|------------------------------------|------------------------------------------|
| `{{ IDENT }}`            | `{{ GIT_ROOT_DIR }}`               | Value from resolved generators           |
| `{{ secret:IDENT }}`     | `{{ secret:DB_PASS_FILE }}`        | Contents of file at path stored in IDENT |
| `{{ provider:NAME.FN }}` | `{{ provider:git.top-level-dir }}` | Calls fn from provider manifest          |

## Commands

```nushell
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

| Profile   | What runs                                                  |
|-----------|------------------------------------------------------------|
| `envfile` | Parse generators + render `.env`                           |
| `secrets` | Generate missing secrets via providers, write via backends |
| `certs`   | Generate PKI certificate chains                            |
| `all`     | envfile + secrets + certs                                  |

## Environment variables

| Variable         | Default        | Effect                     |
|------------------|----------------|----------------------------|
| `ENVCTL_CONFIG`  | `.envctl.toml` | Override config path       |
| `ENVCTL_STAGE`   | `dev`          | Override stage             |
| `ENVCTL_DRY_RUN` | `false`        | Enable dry-run (no writes) |
| `ENVCTL_QUIET`   | `false`        | Suppress non-error output  |

## Built-in providers

| Provider   | Token                                       | Config                                        |
|------------|---------------------------------------------|-----------------------------------------------|
| `git`      | `{{ provider:git.top-level-dir }}`          | none (override with `ENVCTL_GIT_ROOT`)        |
| `password` | `{{ provider:password.generate-password }}` | `length`, `charset`, `tool`                   |
| `compose`  | `{{ provider:compose.collect-files }}`      | `base_dir`, `base_files`, `services`          |
| `certs`    | (used internally by `envctl certs`)         | `tool`, `key_bits`, `organization`, `country` |

## Built-in backends

| Backend | Writes to             |
|---------|-----------------------|
| `file`  | Local filesystem path |

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

See [Architecture](https://arttet.github.io/envctl/guide/architecture.html) for the execution flow and layer responsibilities.

## License

MIT — see [LICENSE](LICENSE).
