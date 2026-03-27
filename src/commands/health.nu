# ==============================================================================
# commands/health.nu — Health monitoring across all profiles.
#
# Thin CLI wrapper over runtime/health/run.nu.
#
# Commands:
#   envctl health                    — all profiles
#   envctl health --profile envfile  — envfile drift + generators
#   envctl health --profile secrets  — secrets exists + age + cert expiry
# ==============================================================================

use ../runtime/health/run.nu [run-health-checks, health-all]
use ../state/state.nu [audit-summary]
use ../language/keywords.nu [profiles]
use ../core/log.nu

# Run health checks for all profiles or a specific profile.
@example "Health check all profiles" { envctl health }
@example "Health check envfile only" { envctl health --profile envfile }
@example "Health check secrets only" { envctl health --profile secrets }
export def "envctl health" [
    --profile: string  # Profile to check: envfile | secrets | all (default: all)
    --quiet            # Suppress informational output
    --config: string   # Override config path
]: nothing -> nothing {
    if $quiet {
        log set-quiet true
    }

    let active_profile = ($profile | default all)
    if $active_profile != all and not ($active_profile in (profiles)) {
        log error --ns health $"unknown profile '($active_profile)' — expected: envfile, secrets, all"
        return
    }

    let cli = {
        config_path: ($config | default $env.ENVCTL_CONFIG)
        stage: $env.ENVCTL_STAGE
        dry_run: false
        quiet: $quiet
    }

    let all_ok = if $active_profile == all {
        health-all $cli
    } else {
        run-health-checks $cli $active_profile
    }

    # Audit summary
    log detail --ns health "recent activity:"
    let summary = (audit-summary)
    if ($summary | is-empty) {
        log detail --ns health "no activity recorded yet"
    } else {
        for e in $summary {
            log detail --ns health $"($e.profile): ($e.action) by ($e.by) at ($e.at)"
        }
    }

    if $all_ok {
        log success --ns health "all checks passed"
    } else {
        log error --ns health "some checks failed"

        return (error make --unspanned { msg: "health checks failed" })
    }
}
