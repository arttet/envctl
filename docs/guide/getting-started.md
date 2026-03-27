# Quick Start

Get up and running with `envctl` in your project in just a few steps.

## 1. Initial Setup

Start by initializing `envctl` in your project's root. This will create a basic configuration and setup necessary files.

```nushell
envctl init
```

This command:
- Creates `.envctl.toml` (from an example if it exists).
- Ensures `.env.example` exists.
- Creates an empty `.envctl.lock`.
- Appends `.env` and `.envctl/` to your `.gitignore`.

Alternatively, you can manually copy the example configuration:

```bash
cp examples/.envctl.example.toml .envctl.toml
```

## 2. Generate Environment File

The most common use case is generating a `.env` file from a template (like `.env.example`).

```nushell
envctl envfile generate
```

This will parse your `.envctl.toml`, resolve any tokens, and write the `.env` file.

## 3. Generate Secrets

If your configuration includes secrets, you can generate them automatically:

```nushell
envctl secrets generate
```

Missing secrets defined in your config will be generated using the configured providers (like a random password) and saved to your specified backends (like a local file).

## 4. Generate PKI Certificates

If you need a local certificate chain (Root CA → Intermediate → Leaf), use:

```nushell
envctl certs generate
```

This uses `openssl` under the hood to create the entire chain based on your configuration.

## 5. Check System Health

To verify that all your configuration and generated assets are in order:

```nushell
envctl health
```

This command checks for configuration drift, missing secrets, or invalid certificate chains.

## 6. Version Control

- **Commit**: `.envctl.toml` and `.envctl.lock`. These define your environment's state.
- **Ignore**: `.env` and the `.envctl/` directory. These contain sensitive or machine-specific data.

Add these to your `.gitignore`:
```text
.env
.envctl/
```
