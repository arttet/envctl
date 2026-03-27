# Plugins Reference

`envctl` features a modular architecture that separates data sources (**Providers**) from storage mechanisms (**Backends**).

## Providers

Providers generate or fetch dynamic data for use in your configuration.

### `git`
Provides information about the current git repository.

- **Tokens**:
  - <span v-pre>`{{ provider:git.top-level-dir }}`</span>: Returns the absolute path to the repository's root directory.
- **Environment Variables**:
  - `ENVCTL_GIT_ROOT`: Manually override the detected root directory.

---

### `password`
Generates cryptographically secure random passwords.

- **Tokens**:
  - <span v-pre>`{{ provider:password.generate-password }}`</span>: Generates a new password.
- **Configuration (`[providers.password]`)**:
  - `length` (int, default 32): Length of the generated password.
  - `charset` (string, default "alphanumeric"): Character set to use (`hex`, `base64`, `symbols`, `alphanumeric`).
  - `tool` (string, default "internal"): External tool to use for generation (`openssl`, `pwgen`, etc.).
- **Environment Variables**:
  - `ENVCTL_PASSWORD_LENGTH`: Override configured length.
  - `ENVCTL_PASSWORD_CHARSET`: Override configured charset.

---

### `compose`
Collects information from Docker Compose files.

- **Tokens**:
  - <span v-pre>`{{ provider:compose.collect-files }}`</span>: Lists relevant Compose files based on configuration.
- **Configuration (`[providers.compose]`)**:
  - `base_dir`: Directory to search for Compose files.
  - `base_files`: List of base Compose files (e.g., `["docker-compose.yml"]`).
  - `services`: List of services to include.

---

### `certs`
Internal provider used by the `envctl certs` commands to manage PKI chains.

- **Configuration (`[certs]`)**:
  - `tool`: Path to `openssl`.
  - `key_bits`: Default RSA key length.
  - `organization`, `country`: Certificate subject defaults.

---

## Backends

Backends define how and where resolved secrets are stored.

### `file`
Stores secrets as plain text files on the local filesystem.

- **Options (`[secrets.NAME.options.file]`)**:
  - `path`: The absolute or relative path where the secret should be written.
  - `permissions` (octal): Optional file permissions (e.g., `0600`).
