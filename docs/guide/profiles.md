# Profiles

Profiles allow you to control which parts of your environment configuration are executed. This is useful for separating standard environment variable generation from more sensitive tasks like secret and certificate generation.

## Available Profiles

| Profile | Command Prefix | Description |
|---|---|---|
| **envfile** | `envctl envfile` | Generates `.env` from your template and resolving generator tokens. |
| **secrets** | `envctl secrets` | Generates and delivers secrets as defined in your configuration. |
| **certs** | `envctl certs` | Generates and manages your local PKI certificate chains. |
| **all** | `envctl health` (uses `all` by default) | Processes all phases in order: envfile → secrets → certs. |

## Why Use Profiles?

1.  **Safety**: You can safely generate environment variables without accidentally rotating sensitive secrets.
2.  **Performance**: If you only need to update your `.env` file, you don't need to wait for certificate checks or secret generation.
3.  **Context**: Different team members might only have permissions for certain profiles (e.g., developers only run `envfile`, while security runs `secrets`).

## Setting Profiles via Environment Variables

You can also specify the current profile stage using the `ENVCTL_STAGE` environment variable:

```bash
# Override the stage for all envctl commands
export ENVCTL_STAGE=production
```

This stage can be referenced within your `.envctl.toml` to dynamically adjust configurations.
