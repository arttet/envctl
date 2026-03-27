# ==============================================================================
# commands/generate.nu — Full pipeline: envfile + secrets + certs in one pass.
# ==============================================================================

use ../runtime/pipeline.nu [run]
use ../core/log.nu
use ../core/constants.nu [DEFAULT_STAGE]

# Generate everything: .env, secrets, and certs in one pass.
#
# Runs envfile → secrets → certs in the correct dependency order.
# Equivalent to: envfile generate && secrets generate && certs generate
@example "Generate everything"     { envctl generate }
@example "Preview without writing" { envctl generate --dry-run }
@example "Generate for prod"       { envctl generate --stage prod }
export def "envctl generate" [
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

    run $cli "all" | ignore
}
