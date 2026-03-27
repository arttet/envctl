# ==============================================================================
# runtime/ctx.nu — Assembled execution state.
#
# ctx is built once per command invocation — immutable after creation.
# Not config, not plugin, not language — point of assembly.
#
# Pipeline:
#   engine/parser.nu → ctx assemble → providers load → compile → execute
#
# CLI passes only overrides: stage, dry_run, quiet, config_path.
# template, env_file, secrets_root always come from AST — CLI cannot override.
#
# Nushell does not enforce record immutability at runtime.
# Immutability is a contract enforced by convention and tests.
# ==============================================================================

use ../engine/queries.nu

use ../engine/parser.nu [parse-config]
use ../language/grammar.nu [parse-env-string]
use ../core/constants.nu [DEFAULT_CONFIG_PATH, DEFAULT_STAGE]

use ../core/log.nu

# Build immutable ctx — assembled execution state passed to all providers.
# engine/parser → queries → ctx assemble
@example "Build ctx for dev" { build-ctx {stage: dev, config_path: .envctl.toml} }
@example "Build ctx with dry-run" { build-ctx {stage: dev, dry_run: true, config_path: .envctl.toml} }
@example "Build ctx for prod quiet" { build-ctx {stage: prod, quiet: true, config_path: .envctl.toml} }
@example "Build ctx minimal" { build-ctx {config_path: .envctl.toml} }
export def build-ctx [
    cli: record   # CLI overrides: stage, dry_run, quiet, config_path
]: nothing -> record {

    let config_path = ($cli | get --optional config_path | default $env.ENVCTL_CONFIG)
    let ast = (parse-config $config_path)
    let env_file = (queries env-file $ast)

    {
        ast: $ast
        cfg: $ast.cfg
        template: (
            # Full AST: passed to engine phases
            # Convenience accessors: derived from AST
            queries template $ast
        )
        env_file: $env_file
        secrets_root: (queries secrets-root $ast)
        env_vars: (parse-env-file $env_file)
        stage: (
            # Runtime flags: CLI → ENV → fallback
            $cli | get --optional stage | default ($env | get --optional ENVCTL_STAGE | default $DEFAULT_STAGE)
        )
        dry_run: ($cli | get --optional dry_run | default (($env | get --optional ENVCTL_DRY_RUN | default "false") == "true"))
        quiet: ($cli | get --optional quiet | default (($env | get --optional ENVCTL_QUIET | default "false") == "true"))
        cli: $cli
    }
}

# Return a new ctx with env_vars reloaded from disk.
# Call after secrets generate to pick up newly written secret paths.
# Does NOT mutate the original ctx — returns a new record.
@example "Reload env_vars after secrets written" { reload-env-vars (build-ctx {config_path: .envctl.toml}) }
export def reload-env-vars [ctx: record] {
    $ctx | upsert env_vars (parse-env-file $ctx.env_file)
}

# Parse .env file into flat key→value record.
def parse-env-file [env_file: path] {
    if not ($env_file | path exists) {
        return {}
    }

    open --raw $env_file | parse-env-string
}
