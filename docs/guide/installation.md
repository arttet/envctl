# Installation

`envctl` is a Nushell-native tool. To use it, you need to have [Nushell](https://www.nushell.sh/) installed.

## Prerequisites

- **Nushell**: Version 0.94 or higher.
- **openssl**: Version 3.0 or higher (required for secrets and certificates).
- **git**: Required if you use the `git` provider.

## Quick Install (no download needed)

If you don't have the repository, you can install directly from GitHub in one command:

```sh
curl -sSL https://raw.githubusercontent.com/arttet/envctl/main/install.nu | nu
```

To install a specific release tag:

```sh
curl -sSL https://raw.githubusercontent.com/arttet/envctl/main/install.nu | nu - --ref v1.0.0
```

The script will automatically download the release archive from GitHub, extract it, and install `envctl`.

## Install from a cloned repository

If you already have the repository cloned, run the installer from the repo root:

```nushell
nu install.nu
```

The installer will:

1. Copy the source files to a default location.
2. Register an autoload hook in Nushell's vendor autoload directory.

### Custom installation prefix

```nushell
nu install.nu --prefix ~/.my-tools/envctl
```

### Skip the autoload hook

```nushell
nu install.nu --no-autoload
```

### Dry run

To see what the installer would do without making any changes:

```nushell
nu install.nu --dry-run
```

### Uninstall

```nushell
nu install.nu --uninstall
```

## Default installation paths

| OS | Default path |
|---|---|
| **Linux / macOS** | `~/.local/share/envctl` |
| **Windows** | `%LOCALAPPDATA%\envctl` |

## Local project use (without installation)

If you prefer not to install `envctl` globally, you can run it directly from its source directory:

```nushell
nu <path-to-envctl>/envctl.nu envctl [command]
```

## Troubleshooting

If the commands are not available after installation, restart your Nushell session or verify that `$nu.vendor-autoload-dirs` includes the path used by the installer.
