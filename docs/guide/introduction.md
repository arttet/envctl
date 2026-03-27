# Introduction

**envctl** is a Nushell-native configuration compiler and execution engine for environment and secrets management. It provides a declarative way to manage your application's environment configuration, secrets, and PKI certificate chains.

## Key Features

- **.env Generation**: Generate `.env` files from declarative templates.
- **Secret Management**: Generate secrets and deliver them to multiple backends (local files, Infisical, etc.).
- **PKI Management**: Manage certificate chains (Root CA → Intermediate → Leaf) as part of your secrets pipeline.
- **Schema Validation**: Every configuration and runtime context is validated against TOML-based schemas.
- **Drift Detection**: Detect and report differences between your declarative config and the actual state on disk or in backends.
- **Nushell Native**: Leverages the power of Nushell for type-safe and performant execution.

## The Two-Phase Model

envctl operates on a strict two-phase execution model to ensure safety and predictability:

### 1. Compile Phase (Pure)
The compiler parses your `.envctl.toml` configuration, validates it against schemas, and builds an immutable Abstract Syntax Tree (AST). This phase is purely deterministic and has no side effects.
- **Parse**: Read `.envctl.toml` and tokenize expressions.
- **Validate**: Check configuration against schemas and link tokens.
- **Plan**: Create an execution plan based on the requested profile.

### 2. Execute Phase (Side Effects)
The executor takes the validated plan and applies the necessary changes to the system.
- **Apply**: Renders templates, calls backends to write secrets, and generates certificates.
- **Log**: Updates the lock file and records the action in the state log.

## Profiles

envctl uses "profiles" to control which parts of the configuration are executed:

| Profile | Description |
|---|---|
| `envfile` | Only generate and manage the `.env` file. |
| `secrets` | Only generate and manage secrets (including certificates). |
| `all` | Execute both `envfile` and `secrets` phases. |
