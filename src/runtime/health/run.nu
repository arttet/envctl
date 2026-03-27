# ==============================================================================
# runtime/health/run.nu — Health check orchestrators.
#
# Extracted from commands/health.nu to allow reuse outside the CLI layer.
# commands/health.nu is a thin CLI wrapper over these functions.
#
# Functions:
#   run-health-checks — run checks for a single profile, returns bool (all ok)
#   health-all        — run checks for all profiles, returns bool (all ok)
# ==============================================================================

use ../../engine/diff.nu [diff-files, is-in-sync]
use ../pipeline.nu [compile]

use ../backends/dispatch.nu [dispatch-health]
use ./checks.nu [check-file]

use ../../core/log.nu

# Run health checks for a single profile.
# Returns true if all checks passed.
@example "Run envfile health checks" { run-health-checks {stage: dev, config_path: .envctl.toml, dry_run: false, quiet: false} envfile }
@example "Run secrets health checks" { run-health-checks {stage: dev, config_path: .envctl.toml, dry_run: false, quiet: false} secrets }
export def run-health-checks [cli: record, profile: string] {
    match $profile {
        "envfile" => (run-envfile-checks $cli)
        "secrets" => (run-secrets-checks $cli)
        _ => {
            log error --ns health $"unknown profile: ($profile)"
            false
        }
    }
}

# Run health checks for all profiles.
# Returns true if all checks passed across all profiles.
@example "Run all health checks" { health-all {stage: dev, config_path: .envctl.toml, dry_run: false, quiet: false} }
export def health-all [cli: record] {
    let envfile_ok = (run-envfile-checks $cli)
    let secrets_ok = (run-secrets-checks $cli)

    $envfile_ok and $secrets_ok
}

def run-envfile-checks [cli: record] {
    log info --ns health "envfile checks"

    mut ok = true
    let rt = try { compile $cli envfile } catch {|err|
        log error --ns health $"  [✗] compile failed: ($err.msg)"
        return false
    }

    # Check: template exists
    let tmpl_check = (check-file $rt.ctx.template)
    if $tmpl_check.ok { log info --ns health $"[✓] template: ($rt.ctx.template)" } else {
        log warn --ns health $"[!] ($tmpl_check.info)"
        $ok = false
    }

    # Check: .env exists (warning only — user must run envctl envfile generate)
    let env_check = (check-file $rt.ctx.env_file)
    if $env_check.ok { log info --ns health $"[✓] env file: ($rt.ctx.env_file)" } else {
        log warn --ns health $"[!] ($env_check.info) — run: envctl envfile generate"
    }

    # Check: drift (warning only — .env may not have been regenerated yet)
    if ($rt.ctx.template | path exists) and ($rt.ctx.env_file | path exists) {
        let drift = (diff-files $rt.ctx.template $rt.ctx.env_file)
        if (is-in-sync $drift) {
            log info --ns health $"[✓] no drift"
        } else {
            log warn --ns health $"[!] drift — ($drift.added | length) added, ($drift.removed | length) removed"
        }
    }

    # Check: generators resolve without error
    let unresolved = ($rt.plan.generators | transpose key value | where {|it| $it.value | str contains "{{" })
    if ($unresolved | is-not-empty) {
        for e in $unresolved {
            log warn --ns health $"[!] unresolved generator: ($e.key) = ($e.value)"
        }
        $ok = false
    } else {
        log info --ns health $"[✓] all generators resolved"
    }

    $ok
}

def run-secrets-checks [cli: record] {
    log info --ns health "secrets checks"
    mut ok = true
    let rt = try { compile $cli secrets } catch {|err|
        log error --ns health $"[✗] compile failed: ($err.msg)"
        return false
    }

    let secret_actions = ($rt.plan.actions | where kind == write-secret)
    if ($secret_actions | is-empty) {
        log info --ns health "no secrets declared"
        return true
    }

    let ctx_with_providers = ($rt.ctx | upsert providers $rt.providers)
    for action in $secret_actions {
        let health = (
            try {
                dispatch-health $action.backend $ctx_with_providers $action.key $action.options
            } catch {|err|
                {
                    ok: false
                    info: $"health check failed: ($err.msg)"
                }
            }
        )

        if $health.ok {
            log info --ns health $"[✓] ($action.key) — ($health.info)"
        } else {
            log warn --ns health $"[✗] ($action.key) — ($health.info)"
            $ok = false
        }
    }

    $ok
}
