# ==============================================================================
# commands/secrets.nu — Secret lifecycle management.
#
# All orchestration delegated to runtime/pipeline.nu.
# This file: parse CLI flags → build cli record → call pipeline.
#
# Commands:
#   envctl secrets generate    — write missing secrets
#   envctl secrets rotate      — rotate one secret by key
#   envctl secrets rotate-all  — rotate all secrets
# ==============================================================================

use ../runtime/pipeline.nu [run, compile]
use ../engine/plan.nu [set-rotate-mode, set-rotate-one]
use ../engine/executor.nu [apply]
use ../state/state.nu [append-entry]
use ../core/log.nu

# Generate missing secret files for all declared secrets in .envctl.toml.
#
# Skips secrets that already exist in their backend — safe to call multiple times.
@example "Generate secrets for dev" { envctl secrets generate }
@example "Generate secrets for prod" { envctl secrets generate --stage prod }
@example "Preview without writing" { envctl secrets generate --dry-run }
export def "envctl secrets generate" [
    --stage:  string   # Active stage
    --dry-run          # Print what would be written, no files created
    --quiet            # Suppress informational output
    --config: string   # Override config path
]: nothing -> nothing {
    if $quiet {
        log set-quiet true
    }

    let cli = {
        config_path: ($config | default $env.ENVCTL_CONFIG)
        stage: ($stage | default $env.ENVCTL_STAGE)
        dry_run: ($dry_run or ($env.ENVCTL_DRY_RUN == "true"))
        quiet: $quiet
    }

    run $cli secrets | ignore
}

# Rotate a single secret by key — overwrite with new value and backup existing.
#
# Pattern-based secrets: re-generates from value_source.
# File backend: backs up existing file as <path>.bak before overwriting.
@example "Rotate one secret" { envctl secrets rotate --key MYSQL_ROOT_PASSWORD_FILE }
@example "Rotate one secret prod" { envctl secrets rotate --key MYSQL_ROOT_PASSWORD_FILE --stage prod }
export def "envctl secrets rotate" [
    --key:    string   # Secret key to rotate (as declared in .envctl.toml)
    --stage:  string   # Active stage
    --dry-run          # Print what would happen, no writes
    --quiet            # Suppress informational output
    --config: string   # Override config path
]: nothing -> nothing {

    if $quiet {
        log set-quiet true
    }

    if ($key | is-empty) {
        log error "[secrets rotate] --key is required"
        return
    }

    let cli = {
        config_path: ($config | default $env.ENVCTL_CONFIG)
        stage: ($stage | default $env.ENVCTL_STAGE)
        dry_run: ($dry_run or ($env.ENVCTL_DRY_RUN == "true"))
        quiet: $quiet
    }

    # Compile secrets pipeline — pure
    let rt = (compile $cli secrets)

    # Patch plan — set rotate mode for the named key only
    let rotated_plan = (set-rotate-one $rt.plan $key)
    let rt = ($rt | upsert plan $rotated_plan)
    if $rt.ctx.dry_run {
        log info $"[secrets] [dry-run] would rotate: ($key)"
        return
    }

    let ctx_with_providers = ($rt.ctx | upsert providers $rt.providers)
    apply $rt.plan $ctx_with_providers | ignore
    append-entry $"secrets rotate ($key)" $rt.ctx.stage "secrets" false

    log success --ns secrets $"rotated: ($key)"
}

# Rotate all secret files declared in .envctl.toml.
#
# Overwrites all secrets regardless of existence. Backs up each file before overwriting.
@example "Rotate all secrets" { envctl secrets rotate-all }
@example "Rotate all secrets for prod" { envctl secrets rotate-all --stage prod }
export def "envctl secrets rotate-all" [
    --stage:  string   # Active stage
    --dry-run          # Print what would happen, no writes
    --quiet            # Suppress informational output
    --config: string   # Override config path
]: nothing -> nothing {
    if $quiet {
        log set-quiet true
    }

    let cli = {
        config_path: ($config | default $env.ENVCTL_CONFIG)
        stage: ($stage | default $env.ENVCTL_STAGE)
        dry_run: ($dry_run or ($env.ENVCTL_DRY_RUN == "true"))
        quiet: $quiet
    }

    # Compile secrets pipeline — pure
    let rt = (compile $cli secrets)

    # Patch plan — set rotate mode for all secrets
    let rotated_plan = ($rt.plan | set-rotate-mode)
    let rt = ($rt | upsert plan $rotated_plan)
    if $rt.ctx.dry_run {
        log info --ns secrets $"[dry-run] would rotate all secrets:"
        for action in ($rt.plan.actions | where kind == "write-secret") { log detail --ns secrets $"  ($action.key) → ($action.backend)" }
        return
    }

    let ctx_with_providers = ($rt.ctx | upsert providers $rt.providers)
    apply $rt.plan $ctx_with_providers | ignore
    append-entry "secrets rotate-all" $rt.ctx.stage "secrets" false

    log success --ns secrets "all secrets rotated"
}
