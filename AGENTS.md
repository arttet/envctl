# AGENTS.md — envctl

> AI coding agent instructions for the **envctl** project.
> Read this fully before making any changes.

---

## Project Overview

**envctl** is a Nushell-native configuration compiler and execution engine for environment and secrets management.

It manages:

- `.env` generation from declarative templates
- Secret generation and multi-backend delivery (local files, Infisical, and more)
- PKI certificate chains (Root CA → Intermediate → Leaf) — part of secrets pipeline
- Schema-driven validation for configs, providers, and runtime ctx
- Drift detection and health monitoring

**Two-phase model:**

- **Compile phase** — pure, deterministic, no side effects: parse → validate → plan
- **Execute phase** — side effects: executor applies plan → backends write → lock updated

**Language:** Nushell only. No Bash, Python, Ruby, or other languages in `src/` or `plugins/`.
**Config format:** TOML — file must be named `.envctl.toml`
**Test runner:** `nu run_tests.nu`

**Versioning roadmap:**

- **v1** — Pure Nushell, stable pipeline, profiles `envfile` / `secrets` / `all`
- **v2** (future) — Rust core engine + Lua plugin runtime

---

## Architectural Model

```text
Config Compiler + Execution Engine
```

### Profile-aware execution

| Profile | Compile Phase | Execute Phase |
|---|---|---|
| `envfile` | parse generators + template tokens | write `.env` only |
| `secrets` | parse secrets + value_source | write secrets only (includes certs) |
| `all` | parse everything | write `.env` + secrets |

Flow:

```text
CLI flags / ENVCTL_* env vars
    ↓
runtime/pipeline.nu              ← profile switch — main orchestrator
    ↓
engine/parser.nu                 ← .envctl.toml → full AST
                                   uses language/grammar.nu for {{ }} tokenization
    ↓
engine/envfile_ast.nu            ← full AST → envfile subtree   (profile: envfile + all)
engine/secrets_ast.nu            ← full AST → secrets subtree   (profile: secrets + all)
    ↓
engine/validator.nu              ← schema checks + token linking via manifest.provides
    ↓
engine/plan.nu                   ← validated AST + profile → ExecutionPlan
                                   resolves generator values
    ↓
engine/executor.nu               ← ExecutionPlan → side effects
                                   renders .env, calls runtime/backends/dispatch.nu
    ↓
engine/diff.nu                   ← resolved plan + disk → drift report
    ↓
pipeline.nu writes lock + state  ← only after executor succeeds, only if not dry-run
```

### Layer responsibilities

| Layer | Responsibility | Key files |
|---|---|---|
| `language/` | Pure language utilities — tokenization, .env.example parsing, keywords | `grammar.nu`, `keywords.nu` |
| `engine/` | Formal compiler: parse → project → validate → plan → execute → diff | `parser.nu`, `envfile_ast.nu`, `secrets_ast.nu`, `validator.nu`, `plan.nu`, `executor.nu`, `diff.nu`, `queries.nu` |
| `schema/` | Universal validation engine — no project knowledge | `validate.nu` |
| `runtime/` | Orchestration — ctx, pipeline, provider/backend loading, dispatch, health | `ctx.nu`, `pipeline.nu`, `providers/`, `backends/`, `health/` |
| `state/` | Reproducibility and audit — lock file, state log | `lock.nu`, `state.nu` |
| `commands/` | CLI interface only — calls pipeline, never calls engine/language/plugins directly | `envfile.nu`, `secrets.nu`, `certs.nu`, `providers.nu`, `health.nu` |
| `core/` | Constants and logging only | `constants.nu`, `log.nu` |
| `plugins/` | Pure plugin payloads — manifest contract only, no src/ dependencies | `providers/`, `backends/` |

**Removed layers — absorbed:**

| Removed | Absorbed into | Reason |
|---|---|---|
| `config/loader.nu` + `defaults.nu` | `engine/parser.nu` | loading is part of parse phase |
| `config/queries.nu` | `engine/queries.nu` | pure getters over AST |
| `language/generator/` | `engine/validator.nu` + `engine/plan.nu` | linking and resolution are engine concerns |
| `language/template/parse.nu` | `language/grammar.nu` | pure token work belongs in grammar |
| `language/template/render.nu` | `engine/executor.nu` | render happens at execute time |
| `language/template/diff.nu` | `engine/diff.nu` | diff is an engine concern |
| `src/plugins/providers/registry.nu` | `src/runtime/providers/registry.nu` | loading is orchestration, not plugin payload |
| `src/plugins/backends/registry.nu` | `src/runtime/backends/registry.nu` | loading is orchestration, not plugin payload |
| `src/plugins/backends/dispatch.nu` | `src/runtime/backends/dispatch.nu` | dispatch is orchestration, not plugin payload |

---

## Repository Structure

```text
envctl.nu                            # Entry point — export-env + init + generate
.envctl.toml                         # Project config — ALWAYS this extension
.envctl.example                      # Config template — copy to .envctl.toml
.envctl.lock                         # Auto-generated — commit this file
.envctl.state.ndjson                 # Local audit log — add to .gitignore

plugins/                             # Pure plugin payloads — manifest contract only
  providers/                         # No dependencies on src/
    git.nu                           # manifest: provides top-level-dir
    password.nu                      # manifest: provides generate-password
    compose.nu                       # manifest: provides collect-files, path-separator
    certs.nu                         # manifest: provides generate-root, generate-intermediate, generate-leaf
  backends/
    file.nu                          # manifest + write_fn, exists_fn, health_fn

schemas/                             # TOML schema files — single source of truth
  envctl.config.schema.toml
  ctx.schema.toml
  secret.schema.toml
  git.config.schema.toml
  git.health.schema.toml
  compose.config.schema.toml
  compose.health.schema.toml
  password.config.schema.toml
  password.health.schema.toml
  certs.config.schema.toml
  certs.health.schema.toml
  file.config.schema.toml
  file.health.schema.toml

src/
  language/                          # Pure language utilities — no side effects
    grammar.nu                       # parse-tokens, classify-expr, resolve-token
                                     # tokenize-env, extract-env-keys, extract-needed-keys
    keywords.nu                      # Reserved words registry — SINGLE SOURCE OF TRUTH

  engine/                            # Formal compiler — all compile phases
    parser.nu                        # .envctl.toml → full AST (absorbs config/loader + defaults)
    envfile_ast.nu                   # full AST → envfile subtree
    secrets_ast.nu                   # full AST → secrets subtree
    validator.nu                     # schema + token linking + manifest.provides
    plan.nu                          # validated AST + profile → ExecutionPlan
    executor.nu                      # ExecutionPlan → side effects + .env render
    diff.nu                          # resolved plan + disk → drift report
    queries.nu                       # pure getters over AST

  schema/
    validate.nu                      # validate-schema, apply-defaults — pure engine

  runtime/                           # Orchestration layer
    ctx.nu                           # build-ctx — assembled execution state
    pipeline.nu                      # profile switch: compile → execute → lock → state
    providers/
      registry.nu                    # load-providers, list-providers
                                     # ONLY file that imports plugins/providers/*.nu
    backends/
      registry.nu                    # load-backend, load-plan-backends
                                     # ONLY file that imports plugins/backends/*.nu
      dispatch.nu                    # dispatch-write, dispatch-exists, dispatch-health
    health/
      run.nu                         # health-all, run-health-checks
      checks.nu                      # check types: tool, file, cert_expiry, secret_age

  state/
    lock.nu                          # read-lock, write-lock, check-versions
    state.nu                         # append-entry, read-state, audit-summary

  core/
    constants.nu                     # DEFAULT_* path constants
    log.nu                           # log info | warn | error | success | detail

  commands/
    envfile.nu                       # envctl envfile generate | diff
    secrets.nu                       # envctl secrets generate | rotate | rotate-all
    certs.nu                         # envctl certs status | renew | renew-all
    plugins.nu                       # envctl plugins list
    health.nu                        # envctl health [--profile] — thin CLI wrapper over runtime/health/run.nu
```

---

## Keywords Registry

`src/language/keywords.nu` is the **single source of truth** for all reserved words. Parser, validator, grammar, and registry all import from here — never hardcode reserved strings elsewhere.

```nushell
# Plugin entry point
export const KEYWORD_MANIFEST = "manifest"

# Top-level .envctl.toml keys
export const KEYWORD_SCHEMA     = "schema"
export const KEYWORD_PROVIDERS  = "providers"
export const KEYWORD_GENERATORS = "generators"
export const KEYWORD_SECRETS    = "secrets"
export const KEYWORD_ENVFILE    = "envfile"

# Token grammar prefixes — reserved inside {{ }}
export const KEYWORD_TOKEN_SECRET   = "secret"
export const KEYWORD_TOKEN_PROVIDER = "provider"

# Secrets section — service keys, not secret declarations
export const SECRETS_SERVICE_KEYS = ["base_dir" "excluded"]

# Profile names
export const PROFILES = ["envfile" "secrets" "certs" "all"]
```

---

## Plugin Manifest Contract

`manifest []` is the sole entry point for every plugin. `provider []` is removed.

### Provider manifest

```nushell
export def manifest []: nothing -> record {
    {
        name:          "password"
        version:       "1.0.0"
        kind:          "provider"
        description:   "Generates cryptographically random passwords"
        provides:      ["generate-password"]
        requires:      []
        config_schema: "password.config.schema.toml"
        health_schema: "password.health.schema.toml"
        resolve: {
            "generate-password": { |ctx| generate-password $ctx }
        }
        env_vars: [
            { name: "ENVCTL_PASSWORD_LENGTH",  description: "Override length",  example: "64" }
            { name: "ENVCTL_PASSWORD_CHARSET", description: "Override charset", example: "hex" }
        ]
    }
}
```

### Backend manifest

```nushell
export def manifest []: nothing -> record {
    {
        name:          "file"
        version:       "1.0.0"
        kind:          "backend"
        provides:      ["write-secret" "exists-secret" "health-secret"]
        config_schema: "file.config.schema.toml"
        health_schema: "file.health.schema.toml"
        write_fn:      { |ctx, var, value, options| write-secret $ctx $var $value $options }
        exists_fn:     { |ctx, var, options|         exists-secret $ctx $var $options }
        health_fn:     { |ctx, var, options|         health-secret $ctx $var $options }
    }
}
```

### Certs provider — `secret_kind`

```nushell
export def manifest []: nothing -> record {
    {
        name:        "certs"
        kind:        "provider"
        secret_kind: "cert"     # ← secrets from this provider are cert type
        provides:    ["generate-root" "generate-intermediate" "generate-leaf"]
        ...
    }
}
```

### Plugin boundary rules

- Only `src/runtime/providers/registry.nu` imports from `plugins/providers/*.nu`
- Only `src/runtime/backends/registry.nu` imports from `plugins/backends/*.nu`
- `plugins/` files must NOT import anything from `src/`

---

## AST Structure

`engine/parser.nu` produces an immutable AST. Never mutate it.

```nushell
# Full AST
{
    cfg:        record          # normalized .envctl.toml
    generators: list<record>   # generator nodes
    secrets:    list<record>   # secret nodes
    envfile:    record         # envfile config node
    providers:  record         # provider config per name
}

# Generator node
{
    kind:     "generator"
    key:      "GIT_ROOT_DIR"
    raw:      "{{ provider:git.top-level-dir }}"
    tokens:   [{ type: "provider", name: "git", fn: "top-level-dir", raw: "..." }]
    resolved: null
    errors:   []
}

# Secret node
{
    kind:         "secret"
    key:          "MYSQL_ROOT_PASSWORD_FILE"
    secret_kind:  "password"              # "password" | "cert"
    value_source: "{{ provider:password.generate-password }}"
    src_tokens:   [...]
    targets:      ["file"]
    options:      { file: { path: "secrets/mysql_root_password" } }
    errors:       []
}
```

---

## ExecutionPlan

```nushell
{
    profile:    "secrets"
    dry_run:    false
    generators: { GIT_ROOT_DIR: "/home/user/project" }
    actions: [
        {
            kind:         "write-secret"
            key:          "MYSQL_ROOT_PASSWORD_FILE"
            secret_kind:  "password"
            mode:         "create-only"    # "create-only" | "overwrite"
            backup:       false
            backend:      "file"
            options:      { path: "/home/user/project/secrets/mysql_root_password" }
            secrets_root: "."
        }
    ]
}
```

- `generate` → `mode: "create-only"` — skips if `exists_fn` returns true
- `rotate` → `mode: "overwrite"`, `backup: true` — always writes, backs up existing

---

## Lock and State Files

**`.envctl.lock`** — committed to git, tracks versions only:

```toml
[providers.git]
version = "1.0.0"

[providers.password]
version = "1.0.0"

[backends.file]
version = "1.0.0"
```

**`.envctl.state.ndjson`** — local only, add to `.gitignore`, audit log:

```
{"action":"envfile generate","at":"2026-02-25T12:00:00Z","by":"artyom","stage":"dev","profile":"envfile","dry_run":false}
{"action":"secrets rotate","at":"2026-02-25T11:30:00Z","by":"artyom","stage":"dev","profile":"secrets","dry_run":false}
```

**Lock policy:**

- Written only after executor succeeds
- Never written on dry-run
- If manifest version ≠ lock version → hard error, pipeline does not run
- Providers are independent of profile — `[providers]` section is global

---

## Config Structure (`.envctl.toml`)

```toml
schema = "v1"

[envfile]
file     = ".env"
pattern  = ".env.example"
excluded = []

[secrets]
base_dir = "."

[generators]
GIT_ROOT_DIR = "{{ provider:git.top-level-dir }}"
APP_URL      = "https://{{ APP_DOMAIN }}/api"

[providers]
enabled = ["git", "password"]

[providers.password]
length  = 32
charset = "alphanumeric"

[secrets.MYSQL_APP_PASSWORD_FILE]
value_source = "{{ provider:password.generate-password }}"
targets      = ["file"]

[secrets.MYSQL_APP_PASSWORD_FILE.options.file]
path = "{{ GIT_ROOT_DIR }}/secrets/mysql_app_password"
```

---

## Token Grammar

```
token         ::= "{{" SP? expr SP? "}}"
expr          ::= secret_expr | provider_expr | var_expr
secret_expr   ::= "secret:" IDENT
provider_expr ::= "provider:" IDENT "." IDENT
var_expr      ::= IDENT
```

| Token | Example | Resolves to |
|---|---|---|
| `{{ IDENT }}` | `{{ DB_HOST }}` | Value from resolved generators |
| `{{ secret:IDENT }}` | `{{ secret:DB_PASS_FILE }}` | Content of file at path in IDENT |
| `{{ provider:NAME.FN }}` | `{{ provider:git.top-level-dir }}` | Calls fn from manifest.resolve |

---

## CLI Commands

```
envctl init                              # scaffold .envctl.toml

envctl envfile generate                  # compile + write .env
envctl envfile generate --dry-run
envctl envfile diff                      # compile + diff vs current .env

envctl secrets generate                  # compile + write missing secrets
envctl secrets generate --dry-run
envctl secrets rotate --key NAME         # overwrite + backup one secret
envctl secrets rotate-all

envctl certs status                      # cert secrets: expiry, chain, trust
envctl certs renew --key NAME
envctl certs renew-all

envctl generate                          # profile=all (envfile + secrets)
envctl generate --dry-run

envctl health
envctl health --profile envfile
envctl health --profile secrets

envctl providers list
```

---

## Adding a New Provider

1. Create `plugins/providers/my_provider.nu` — implement `manifest []`
2. No imports from `src/` — plugin must be self-contained
3. Create `schemas/my_provider.config.schema.toml`
4. Create `schemas/my_provider.health.schema.toml`
5. Register in `builtin-providers` in `src/runtime/providers/registry.nu`
6. Add to `[providers.enabled]` in `.envctl.toml`
7. Write `tests/unit/my_provider_test.nu`

## Adding a New Backend

1. Create `plugins/backends/my_backend.nu` — implement `manifest []` + `write_fn`, `exists_fn`, `health_fn`
2. No imports from `src/` — plugin must be self-contained
3. Create `schemas/my_backend.config.schema.toml`
4. Register in `builtin-backends` in `src/runtime/backends/registry.nu`
5. Users add `targets = ["my_backend"]` in `[secrets.NAME]`

---

## Nushell Style Guide

### Typed signatures — always

```nushell
export def my-fn [cfg: record, path: string]: nothing -> list<string> { }
```

### `get --optional` — always, never bare `get`

```nushell
# ✅ correct
let val = ($cfg | get --optional providers.password.length | default 32)

# ❌ wrong — crashes if key missing
let val = ($cfg | get providers.password.length)
```

### Nested record access — step by step

```nushell
# ❌ crashes if options or file is missing
let path = ($spec | get --optional options.file.path | default "")

# ✅ step by step
let opts      = ($spec      | get --optional options | default {})
let file_opts = ($opts      | get --optional file    | default {})
let raw_path  = ($file_opts | get --optional path    | default "")
```

### Multi-line command calls — wrap in parentheses

```nushell
# ❌ wrong
build-file-list
    $selected
    $variants

# ✅ correct
(build-file-list
    $selected
    $variants)
```

### Parentheses in interpolated strings — escape literal parens

```nushell
# ❌ wrong — (s) parsed as command
log success $"All secrets present on disk(s)"

# ✅ correct
log success $"All secrets present on disk\(s\)"
log error   $"($missing | length) secret\(s\) missing"
```

### `open` on `.toml` — never `--raw` or `| from toml`

```nushell
# ❌ wrong
open --raw $path | from toml
open $path | from toml

# ✅ correct — open detects .toml and parses automatically
open $path
```

### Filter service keys — `where + not-in`, never `reject --ignore-errors`

```nushell
# ❌ wrong
$secrets | reject --ignore-errors base_dir

# ✅ correct
$cfg
| get --optional secrets
| default {}
| transpose key val
| where { |e| $e.key not-in (secrets-service-keys) }
| transpose --ignore-titles --header-row
| into record
```

### `match` over chained `if/else`

```nushell
let status = match $days_left {
    _ if $days_left < 0  => "EXPIRED"
    _ if $days_left < 7  => "CRITICAL"
    _ if $days_left < 30 => "WARNING"
    _                    => "OK"
}
```

### `@example` — real executable code, no variables

```nushell
# ❌ wrong — $cfg does not exist at example runtime
@example "Validate" { validate-schema $cfg "envctl.config.schema.toml" }

# ✅ correct
@example "Validate empty record" { validate-schema {} "envctl.config.schema.toml" }
```

### Health handlers — never throw

```nushell
# ✅ correct — always returns record
export def health-secret [ctx: record, var: string, options: record]: nothing -> record {
    if not ($path | path exists) { return { ok: false, info: $"missing: ($path)" } }
    { ok: true, info: $"exists, ($age_info)" }
}
```

### `defer` for cleanup in tests

```nushell
def "test my thing" [] {
    let tmp = (mktemp -d)
    defer { rm -rf $tmp }
}
```

---

## What Not To Do

**Architecture:**

- **Never write Bash, Python, Ruby, or any non-Nushell** in `src/` or `plugins/`
- **Never import `plugins/providers/*.nu` outside `src/runtime/providers/registry.nu`**
- **Never import `plugins/backends/*.nu` outside `src/runtime/backends/registry.nu`**
- **Never import anything from `src/` inside `plugins/`** — plugins must be self-contained
- **Never put orchestration logic in `plugins/`** — plugin payloads are pure manifest + fns
- **Never put side effects in compile phase** — compile is pure and deterministic
- **Never mutate `ctx` or AST** after assembly/parse
- **Never add project knowledge to `src/schema/validate.nu`** — pure engine only
- **Never hardcode validation rules in code** — always use a schema file in `schemas/`
- **Never add a schema file outside `schemas/`**
- **Never add a `{{ }}` token type without updating `language/grammar.nu` AND `language/keywords.nu` first**
- **Never add a reserved word without registering it in `src/language/keywords.nu`**
- **Never use `provider []` in plugins** — replaced by `manifest []`
- **Never call engine/language/runtime directly from `src/commands/`** — always through pipeline
- **Never import between command modules** in `src/commands/`

**Nushell pitfalls:**

- **Never use bare `get`** — always `get --optional`
- **Never use `--ignore-errors`** — filter with `where + not-in`
- **Never use dotted path on nested optional fields** — step down one level at a time
- **Never call multi-line commands without parentheses**
- **Never use bare `(word)` in interpolated strings** — escape as `\(word\)`
- **Never name config file `.envctl`** — must be `.envctl.toml`

**Runtime:**

- **Never throw from a health handler** — always return `{ ok: false, info: "..." }`
- **Never write lock file on dry-run**
- **Never run pipeline if lock version ≠ manifest version** — hard error
- **Never write `.envctl.state.ndjson` on dry-run**

---

## Environment Variables

| Variable | Effect | Default |
|---|---|---|
| `ENVCTL_CONFIG` | Override config path | `.envctl.toml` |
| `ENVCTL_STAGE` | Override `--stage` | `dev` |
| `ENVCTL_DRY_RUN` | Enable dry-run | `false` |
| `ENVCTL_QUIET` | Suppress non-error output | `false` |

Provider-specific variables declared in `manifest.env_vars` — read from `ctx.cli`.

---

## Running

```nushell
nu envctl.nu envctl init
nu envctl.nu envctl generate
nu envctl.nu envctl envfile generate --stage dev
nu envctl.nu envctl secrets generate
nu envctl.nu envctl health
nu envctl.nu envctl providers list
```

## Running Tests

```nushell
nu run_tests.nu
nu run_tests.nu --unit
nu run_tests.nu --file tests/unit/grammar_test.nu
```
