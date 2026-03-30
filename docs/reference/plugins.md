# Plugins Reference

`envctl` has a modular plugin architecture. **Providers** generate or fetch dynamic values. **Backends** store the resolved secrets. Both are declared as plugins under `plugins/` and loaded at runtime via the registry.

## Using provider tokens in `.env.example`

Provider tokens can appear anywhere a value appears — in `[generators]`, in `value_source` fields, in secret `path` options, and directly in `.env.example` template lines.

```bash
# .env.example

# Resolved from [generators] in .envctl.toml
ROOT_DIR={{ GIT_ROOT_DIR }}/data

# Called directly during envfile generate — no generator needed
COMPOSE_PATH_SEPARATOR={{ provider:compose.path-separator }}
COMPOSE_FILE={{ provider:compose.collect-files }}
```

When `envctl envfile generate` runs, it processes the template line by line. Each resolved value becomes available to subsequent lines, so variables defined earlier in the file can be referenced lower down:

```bash
# .env.example
SECRETS_DIR=/run/secrets
DB_PASSWORD_FILE={{ SECRETS_DIR }}/db_password   # uses the line above
```

The three token types available everywhere:

| Token | Example | Resolves to |
|---|---|---|
| <span v-pre>`{{ IDENT }}`</span> | <span v-pre>`{{ GIT_ROOT_DIR }}`</span> | Value from `[generators]` or a previously resolved line |
| <span v-pre>`{{ provider:NAME.FN }}`</span> | <span v-pre>`{{ provider:compose.collect-files }}`</span> | Return value of provider function `FN` |
| <span v-pre>`{{ secret:IDENT }}`</span> | <span v-pre>`{{ secret:DB_PASS_FILE }}`</span> | Contents of the file whose path is in `IDENT` |

::: warning
Every provider used in a token must be listed in `[providers].enabled` in `.envctl.toml`.
A token that cannot be resolved is a **hard error** — the pipeline stops.
:::

---

## Providers

### `git`

Resolves workspace paths from the current git repository.

**Provides**

| Token | Returns |
|---|---|
| <span v-pre>`{{ provider:git.top-level-dir }}`</span> | Absolute path to the repository root (`git rev-parse --show-toplevel`). Falls back to `$PWD` if not in a git repo. |

**Enable**

```toml
[providers]
enabled = ["git"]
```

No additional configuration keys — the `[providers.git]` section is optional and currently empty.

**Environment overrides**

| Variable | Effect |
|---|---|
| `ENVCTL_GIT_ROOT` | Skip `git rev-parse` and use this path directly |

**Usage in `.envctl.toml`**

```toml
[generators]
GIT_ROOT_DIR = "{{ provider:git.top-level-dir }}"

# Derived generators can reference GIT_ROOT_DIR once it is resolved
DATA_DIR     = "{{ GIT_ROOT_DIR }}/data"
SECRETS_DIR  = "{{ GIT_ROOT_DIR }}/secrets"
```

**Usage in `.env.example`**

```bash
# Assumes GIT_ROOT_DIR is declared in [generators]
ROOT_DIR={{ GIT_ROOT_DIR }}/data
VOLUMES_ROOT={{ ROOT_DIR }}/volumes
```

---

### `password`

Generates cryptographically secure random passwords.

**Provides**

| Token | Returns |
|---|---|
| <span v-pre>`{{ provider:password.generate-password }}`</span> | A random password string (length and charset from config) |

**Enable**

```toml
[providers]
enabled = ["password"]
```

**Configuration (`[providers.password]`)**

| Key | Type | Default | Description |
|---|---|---|---|
| `length` | int | `32` | Password length (8–4096) |
| `charset` | string | `"alphanumeric"` | Character set: `alphanumeric`, `hex`, `base64`, `symbols` |
| `tool` | string | `"internal"` | Generation backend: `internal`, `openssl`, `pwgen` |

```toml
[providers.password]
length  = 64
charset = "symbols"
```

**Environment overrides**

| Variable | Effect |
|---|---|
| `ENVCTL_PASSWORD_LENGTH` | Override `length` for this run |
| `ENVCTL_PASSWORD_CHARSET` | Override `charset` for this run |

**Per-secret overrides**

`length`, `charset`, and `tool` can be set directly on any secret entry to override the global `[providers.password]` config for that secret only. Global config and environment variables still apply to all other secrets.

```toml
[providers.password]
length  = 32
charset = "alphanumeric"   # default for all secrets

[secrets.DB_PASSWORD_FILE]
value_source = "{{ provider:password.generate-password }}"
targets      = ["file"]
# uses global config: length=32, charset=alphanumeric

[secrets.JWT_PRIVATE_KEY_FILE]
value_source = "{{ provider:password.generate-password }}"
targets      = ["file"]
length  = 512              # overrides global length for this secret only
charset = "hex"            # overrides global charset for this secret only
```

**Usage — generating a secret**

The password token is used as a `value_source`, not directly in `.env.example`. The `.env.example` line references the secret file path instead:

```toml
# .envctl.toml
[secrets.DB_PASSWORD_FILE]
value_source = "{{ provider:password.generate-password }}"
targets      = ["file"]

[secrets.DB_PASSWORD_FILE.options.file]
path = "{{ GIT_ROOT_DIR }}/secrets/db_password"
```

```bash
# .env.example — reference the path, not the password directly
DB_PASSWORD_FILE={{ SECRETS_PREFIX_DIR }}/db_password
```

```nushell
envctl secrets generate   # writes the password to disk
envctl envfile generate   # renders .env with the path value
```

---

### `rsa`

Generates RSA private keys in PKCS1 or PKCS8 PEM format. Use this for JWT signing keys and any other use case that requires a PEM-encoded RSA key rather than a random string.

**Provides**

| Token | Returns |
|---|---|
| <span v-pre>`{{ provider:rsa.generate-rsa-key }}`</span> | PEM-encoded RSA private key (PKCS1 or PKCS8) |

**Enable**

```toml
[providers]
enabled = ["rsa"]
```

**Configuration (`[providers.rsa]`)**

| Key | Type | Default | Description |
|---|---|---|---|
| `key_bits` | int | `2048` | RSA key size: `2048`, `3072`, or `4096` |
| `format` | string | `"pkcs1"` | Output format: `pkcs1` (`openssl genrsa`) or `pkcs8` (converted via `openssl pkcs8 -topk8 -nocrypt`) |

```toml
[providers.rsa]
key_bits = 2048
format   = "pkcs1"
```

**Per-secret overrides**

`key_bits` and `format` can be set directly on any secret entry to override the global `[providers.rsa]` config for that secret only.

```toml
[providers.rsa]
key_bits = 2048
format   = "pkcs1"   # default for all RSA secrets

[secrets.JWT_PRIVATE_KEY_FILE]
value_source = "{{ provider:rsa.generate-rsa-key }}"
targets      = ["file"]
# uses global config: key_bits=2048, format=pkcs1

[secrets.SERVICE_B_JWT_KEY_FILE]
value_source = "{{ provider:rsa.generate-rsa-key }}"
targets      = ["file"]
key_bits     = 4096    # overrides global key_bits for this secret only
format       = "pkcs8" # overrides global format for this secret only
```

**Usage — generating a JWT signing key**

```toml
# .envctl.toml
[providers]
enabled = ["git", "rsa"]

[generators]
GIT_ROOT_DIR         = "{{ provider:git.top-level-dir }}"
PROJECT_SECRETS_DIR  = "{{ GIT_ROOT_DIR }}/secrets"

[providers.rsa]
key_bits = 2048
format   = "pkcs1"

[secrets.JWT_PRIVATE_KEY_FILE]
value_source = "{{ provider:rsa.generate-rsa-key }}"
targets      = ["file"]

[secrets.JWT_PRIVATE_KEY_FILE.options.file]
path = "{{ PROJECT_SECRETS_DIR }}/jwt_private_key"
```

```bash
# .env.example
JWT_PRIVATE_KEY_FILE={{ PROJECT_SECRETS_DIR }}/jwt_private_key
```

```nushell
envctl secrets generate   # writes the PEM key to disk
envctl envfile generate   # renders .env with the path value
```

::: info
`pkcs1` produces a `-----BEGIN RSA PRIVATE KEY-----` PEM block.
`pkcs8` produces a `-----BEGIN PRIVATE KEY-----` PEM block (unencrypted).
Both formats are accepted by most JWT libraries (e.g. `golang-jwt/jwt`, `jsonwebtoken`, `PyJWT`).
:::

::: warning
RSA key generation is CPU-bound. `key_bits = 4096` may take a few seconds on older hardware.
`key_bits = 2048` is sufficient for HS256/RS256 JWT use cases and generates significantly faster.
:::

---

### `compose`

Builds the `COMPOSE_FILE` and `COMPOSE_PATH_SEPARATOR` values for Docker Compose by discovering relevant Compose files on disk based on the active stage and selected services.

**Provides**

| Token | Returns |
|---|---|
| <span v-pre>`{{ provider:compose.collect-files }}`</span> | OS path-separator-delimited list of Compose file paths that exist on disk |
| <span v-pre>`{{ provider:compose.path-separator }}`</span> | `:` on Linux/macOS, `;` on Windows |

**Enable**

```toml
[providers]
enabled = ["git", "compose"]   # git is needed if base_dir references GIT_ROOT_DIR
```

**Configuration (`[providers.compose]`)**

| Key | Type | Default | Description |
|---|---|---|---|
| `base_dir` | string | `"."` (project root) | Directory where Compose files live. Supports <span v-pre>`{{ GIT_ROOT_DIR }}`</span> substitution. |
| `base_files` | list&lt;string&gt; | `["compose.yml"]` | Base files always included (if they exist on disk). |
| `services` | record | `{}` | Per-service configuration — controls which service files are appended. |

**Service entry keys**

Each key under `[providers.compose.services.NAME]` has a specific meaning:

| Key | Type | Description |
|---|---|---|
| `default` | bool | If `true`, this service is selected automatically. |
| *any other key* | string | A swappable dimension (e.g., `engine`, `cache`). Its value is the default variant. |

The point of dimensions is that the same logical service can be backed by different implementations. For example, a `db` service has an `engine` dimension — the project normally runs `mysql`, but you can switch to `postgres` without touching the config:

```toml
[providers.compose]
base_dir   = "{{ GIT_ROOT_DIR }}"
base_files = ["compose.yml"]

[providers.compose.services.db]
default = true
engine  = "mysql"        # default engine variant

[providers.compose.services.cache]
default = false          # not selected unless ENVCTL_SERVICES overrides
```

**Environment overrides**

| Variable | Format | Effect |
|---|---|---|
| `ENVCTL_SERVICES` | `"svc1,svc2"` | Replace auto-selected services with this comma-separated list |
| `ENVCTL_VARIANTS` | `"svc.dim=variant,..."` | Override variant for a specific service + dimension |

```nushell
# Switch the db service to postgres without changing .envctl.toml
ENVCTL_VARIANTS="db.engine=postgres" envctl envfile generate

# Select db and cache instead of just the defaults
ENVCTL_SERVICES="db,cache" envctl envfile generate

# Combine both: select cache too, and use postgres for db
ENVCTL_SERVICES="db,cache" ENVCTL_VARIANTS="db.engine=postgres" envctl envfile generate
```

**File resolution algorithm**

Files are collected in this order:

1. Each base file in `base_files` — e.g., `{base_dir}/compose.yml`
2. Root stage file — `{base_dir}/compose.{stage}.yml` (optional, for global stage overrides)
3. For each selected service `NAME`:
   - Variant base file — `{base_dir}/{NAME}/compose.{NAME}.{dim}.{variant}.yml`
   - Variant stage file — `{base_dir}/{NAME}/compose.{NAME}.{dim}.{variant}.{stage}.yml`
   - Service base file — `{base_dir}/{NAME}/compose.{NAME}.yml`
   - Service stage file — `{base_dir}/{NAME}/compose.{NAME}.{stage}.yml`

Only files that **actually exist on disk** are included. Missing files are silently skipped.

**Expected directory layout**

```text
{base_dir}/
  compose.yml                                      ← always included (base file)
  compose.dev.yml                                  ← included when --stage dev (root stage override)

  db/
    compose.db.engine.mysql.yml                    ← included when service=db, engine=mysql
    compose.db.engine.mysql.dev.yml                ← included when service=db, engine=mysql, --stage dev
    compose.db.engine.postgres.yml                 ← included when service=db, engine=postgres (variant override)
    compose.db.engine.postgres.dev.yml             ← included when service=db, engine=postgres, --stage dev
    compose.db.yml                                 ← service base, always included when db is selected
    compose.db.dev.yml                             ← included when service=db and --stage dev
    compose.db.prod.yml                            ← included when service=db and --stage prod

  observability/
    compose.observability.metrics.prometheus.yml       ← included when metrics=prometheus
    compose.observability.metrics.prometheus.dev.yml   ← included when metrics=prometheus and --stage dev
    compose.observability.yml                          ← service base
    compose.observability.dev.yml                      ← included when --stage dev
```

**Usage in `.env.example`**

```bash
# .env.example

# OS-correct separator — : on Linux/macOS, ; on Windows
COMPOSE_PATH_SEPARATOR={{ provider:compose.path-separator }}

# Colon/semicolon-delimited list of compose file paths that exist on disk
COMPOSE_FILE={{ provider:compose.collect-files }}
```

**Complete `.envctl.toml` example**

```toml
schema = "v1"

[providers]
enabled = ["git", "compose"]

[generators]
GIT_ROOT_DIR = "{{ provider:git.top-level-dir }}"

[envfile]
file    = ".env"
pattern = ".env.example"

[providers.compose]
base_dir   = "{{ GIT_ROOT_DIR }}"
base_files = ["compose.yml"]

[providers.compose.services.db]
default = true
engine  = "mysql"        # swap to postgres with ENVCTL_VARIANTS="db.engine=postgres"

[providers.compose.services.cache]
default = true
```

After `envctl envfile generate --stage dev`, the `.env` file will contain something like:

```bash
COMPOSE_PATH_SEPARATOR=:
COMPOSE_FILE=/home/user/myproject/compose.yml:/home/user/myproject/compose.dev.yml:/home/user/myproject/db/compose.db.engine.mysql.yml:/home/user/myproject/db/compose.db.engine.mysql.dev.yml:/home/user/myproject/db/compose.db.yml:/home/user/myproject/db/compose.db.dev.yml:/home/user/myproject/cache/compose.cache.yml
```

Order for each selected service: variant base → variant stage → service base → service stage. This means stage-specific overrides always come after the base they override.

---

### `certs`

Internal provider used exclusively by the `envctl certs` commands to generate and manage PKI certificate chains (Root CA → Intermediate CA → Leaf). It is not intended for use in `.env.example` templates.

**Enable**

```toml
[providers]
enabled = ["certs"]
```

**Configuration (`[providers.certs]`)**

| Key | Type | Default | Description |
|---|---|---|---|
| `tool` | string | `"openssl"` | Certificate tool. Currently only `openssl` is supported. |
| `key_bits` | int | `4096` | RSA key size: `2048` or `4096`. |
| `organization` | string | `""` | Default certificate subject organisation. |
| `country` | string | `""` | Default certificate subject country (2-letter code). |

```toml
[providers.certs]
tool         = "openssl"
key_bits     = 4096
organization = "My Company"
country      = "US"
```

Cert chains are declared in `[certs.*]` sections — see the [Commands reference](./commands) for the full `envctl certs` workflow.

---

## Backends

### `file`

Stores secrets as plain text files on the local filesystem. This is the default and only built-in backend.

**Used automatically** when a secret declares `targets = ["file"]`.

**Options (`[secrets.NAME.options.file]`)**

| Key | Type | Description |
|---|---|---|
| `path` | string | Absolute or relative path where the secret will be written. Supports generator tokens. |

For certificate pairs, use `cert` and `key` instead of `path`:

| Key | Type | Description |
|---|---|---|
| `cert` | string | Path for the PEM certificate file. |
| `key` | string | Path for the PEM private key file. |

**Security** — if an explicit `path` is set, the backend validates that the resolved path does not escape `secrets.base_dir` (path traversal protection).

**Example — password secret**

```toml
[secrets.DB_PASSWORD_FILE]
value_source = "{{ provider:password.generate-password }}"
targets      = ["file"]

[secrets.DB_PASSWORD_FILE.options.file]
path = "{{ GIT_ROOT_DIR }}/secrets/db_password"
```

**Example — certificate pair**

```toml
[certs.leaf]
signed_by = "intermediate"
days      = 365
targets   = ["file"]

[certs.leaf.options.file]
cert = "{{ GIT_ROOT_DIR }}/certs/leaf.crt"
key  = "{{ GIT_ROOT_DIR }}/certs/leaf.key"
```

**Usage in `.env.example`**

Secret files are referenced by their path, not their content. The path value often comes from a generator:

```bash
# .env.example
SECRETS_PREFIX_DIR=/run/secrets

# These point to the files that the file backend wrote
DB_PASSWORD_FILE={{ SECRETS_PREFIX_DIR }}/db_password
TLS_CERT_FILE={{ SECRETS_PREFIX_DIR }}/leaf.crt
TLS_KEY_FILE={{ SECRETS_PREFIX_DIR }}/leaf.key
```

To embed the **contents** of a secret file directly into a variable, use the `secret:` token:

```bash
# .env.example — embed the DSN string that was written to a file
DATABASE_DSN={{ secret:DATABASE_DSN_FILE }}
```

::: info
<span v-pre>`{{ secret:IDENT }}`</span> reads the file at the path stored in the `IDENT` generator variable.
The secret file must already exist on disk when `envctl envfile generate` runs —
generate secrets first with `envctl secrets generate`, then generate the env file.
:::
