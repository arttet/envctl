# ==============================================================================
# commands/plugins.nu — Plugin inspection.
#
# Commands:
#   envctl plugins list — show loaded providers, backends and versions from manifest
# ==============================================================================

use ../runtime/ctx.nu [build-ctx]
use ../runtime/providers/registry.nu [list-providers]
use ../runtime/backends/registry.nu [list-backends]
use ../state/lock.nu [read-lock, lock-status]
use ../core/log.nu

# List all loaded providers and backends with versions and manifest details.
#
# Compares manifest versions against lock file — highlights mismatches.
@example "List plugins" { envctl plugins list }
@example "List plugins with custom config" { envctl plugins list --config .envctl.prod.toml }
export def "envctl plugins list" [
    --config: string   # Override config path
    --quiet            # Suppress informational output
]: nothing -> nothing {
    if $quiet {
        log set-quiet true
    }

    let cli = {
        config_path: ($config | default $env.ENVCTL_CONFIG)
        stage: $env.ENVCTL_STAGE
        dry_run: false
        quiet: $quiet
    }

    let ctx = (build-ctx $cli)
    let lock = (read-lock)
    let locked = (lock-status $lock)
    let providers = (list-providers $ctx.ast)
    let backends = (list-backends)

    log info --ns providers "loaded providers:"
    for p in $providers {
        let lock_row = ($locked | where kind == provider and name == $p.name | get --optional 0?)
        let lock_version = ($lock_row | get --optional version | default "not locked")
        let mismatch = ($lock_version != "not locked" and $lock_version != $p.version)
        let version_str = if $mismatch { $"($p.version) ⚠ lock: ($lock_version)" } else { $p.version }

        log info --ns providers $"($p.name) v($version_str)"
        log detail --ns providers $"    provides:    ($p.provides)"

        if ($p.requires | is-not-empty) {
            log detail --ns providers $"    requires:    ($p.requires)"
        }

        if ($p.env_vars | is-not-empty) {
            log detail --ns providers $"    env vars:    ($p.env_vars)"
        }
    }

    log info --ns providers "registered backends:"
    for name in $backends {
        let lock_row = ($locked | where kind == backend and name == $name | get --optional 0?)
        let lock_version = ($lock_row | get --optional version | default "not locked")
        log info --ns providers $"    ($name) — lock: ($lock_version)"
    }
}
