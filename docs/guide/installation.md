# Installation

`envctl` is a Nushell-native tool. To use it, you need to have [Nushell](https://www.nushell.sh/) installed.

## Prerequisites

- **Nushell**: Version 0.94 or higher.
- **openssl**: Version 3.0 or higher (required for secrets and certificates).
- **git**: Required if you use the `git` provider.

## Quick Install

Install directly from GitHub — no clone required:

```nushell
http get https://raw.githubusercontent.com/arttet/envctl/main/install.nu | into string | nu -c $in
```

The installer will automatically download the release archive from GitHub, extract it, and register an autoload hook so all `envctl` commands are available in every new Nushell session.

After installation, restart your Nushell session or run:

```nushell
source ($nu.vendor-autoload-dirs | last | path join envctl_loader.nu)
```

## Default installation paths

| OS | Path |
|---|---|
| **Linux / macOS** | `~/.local/share/envctl` |
| **Windows** | `%LOCALAPPDATA%\envctl` |

## Install from a cloned repository

If you already have the repository cloned, run the installer from the repo root:

```nushell
nu install.nu
```

### Install options

```nushell
nu install.nu --prefix ~/.my-tools/envctl  # custom install directory
nu install.nu --no-autoload                # copy files only, skip hook
nu install.nu --ref v1.0.0                 # install a specific release tag
nu install.nu --dry-run                    # preview without writing anything
nu install.nu --uninstall                  # remove files and autoload hook
```

## Local project use (without installation)

Run directly from source without installing globally:

```nushell
nu <path-to-envctl>/envctl.nu envctl [command]
```

## Troubleshooting

If the commands are not available after installation, restart your Nushell session or verify that `$nu.vendor-autoload-dirs` includes the path used by the installer:

```nushell
$nu.vendor-autoload-dirs
ls ($nu.vendor-autoload-dirs | last)
```
