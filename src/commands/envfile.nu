# ==============================================================================
# commands/envfile.nu — Environment file generation and diff.
#
# All orchestration delegated to runtime/pipeline.nu.
# This file: parse CLI flags → build cli record → call pipeline.
#
# Commands:
#   envctl envfile generate   — compile + write .env
#   envctl envfile diff       — compile + diff vs current .env
# ==============================================================================

use ../runtime/pipeline.nu [run, compile]
use ../engine/diff.nu [diff-env, is-in-sync]
use ../language/grammar.nu [tokenize-env]
use ../core/log.nu
use ../core/constants.nu [DEFAULT_STAGE]

# Generate .env from template.
#
# Resolves {{ provider:... }} and {{ VAR }} via grammar + plugin layer.
# Does NOT write secret files — run `envctl secrets generate` after.
@example "Generate .env for dev stage" { envctl envfile generate }
@example "Generate .env for prod" { envctl envfile generate --stage prod }
@example "Preview without writing" { envctl envfile generate --dry-run }
@example "Use custom config" { envctl envfile generate --config .envctl.prod.toml }
export def "envctl envfile generate" [
    --stage:  string   # Target stage: dev | staging | prod
    --dry-run          # Show what would change, write nothing
    --quiet            # Suppress non-error output
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

    run $cli envfile | ignore
}

# Compare current .env against template — show drift.
#
# Compile phase only — no writes.
@example "Show drift between template and .env" { envctl envfile diff }
@example "Use custom config" { envctl envfile diff --config .envctl.prod.toml }
export def "envctl envfile diff" [
    --quiet            # Suppress non-error output
    --config: string   # Override config path
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

    let rt = (compile $cli envfile)
    if not ($rt.ctx.env_file | path exists) {
        log error --ns envfile $"envfile ($rt.ctx.env_file) not found — run: envctl envfile generate"
        return
    }

    let tokens = (tokenize-env (open --raw $rt.ctx.template))
    let result = (diff-env $tokens $rt.ctx.env_vars)
    if (is-in-sync $result) {
        log success --ns envfile $"($rt.ctx.env_file) is in sync with ($rt.ctx.template)"
        return
    }

    if ($result.added | is-not-empty) {
        log warn --ns envfile $"in template ($rt.ctx.template), missing from ($rt.ctx.env_file):"
        for key in $result.added { log warn --ns envfile $"  [+] ($key)" }
    }

    if ($result.removed | is-not-empty) {
        log warn --ns envfile $"stale in .env ($rt.ctx.env_file), removed from template ($rt.ctx.template):"
        for key in $result.removed { log warn --ns envfile $"  [-] ($key)" }
        return
    }

    log warn --ns envfile "run: envctl envfile generate"
}
