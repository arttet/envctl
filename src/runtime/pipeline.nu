# ==============================================================================
# runtime/pipeline.nu — Profile-aware compile + execute pipeline.
#
# Main orchestrator — called by all commands.
#
# Flow per profile:
#   init    → build ctx + load manifests + check lock versions
#   compile → parse AST → project → validate → plan
#   execute → executor apply → write lock → append state
#
# Profiles: "envfile" | "secrets" | "certs" | "all"
# ==============================================================================

use ./ctx.nu [build-ctx]

use ../engine/parser.nu
use ../engine/ast/envfile.nu
use ../engine/ast/secrets.nu
use ../engine/ast/certs.nu
use ../engine/validator.nu
use ../engine/plan.nu
use ../engine/executor.nu

use ../runtime/providers/registry.nu [load-providers]
use ../runtime/backends/registry.nu [load-plan-backends, load-backend, list-backends]

use ../state/lock.nu [read-lock, check-versions, write-lock]
use ../state/state.nu [append-entry]

use ../language/keywords.nu [is-valid-profile]

use ../core/constants.nu [DEFAULT_LOCK_PATH, DEFAULT_STATE_PATH]
use ../core/log.nu

# Full pipeline: init → compile → execute.
# Returns rt record for commands that need post-execute data (e.g. diff).
@example "Run envfile pipeline"         { run {stage: dev, config_path: .envctl.toml} envfile }
@example "Run secrets pipeline dry-run" { run {stage: dev, dry_run: true, config_path: .envctl.toml} secrets }
@example "Run certs pipeline"           { run {stage: dev, config_path: .envctl.toml} certs }
@example "Run all pipeline"             { run {stage: dev, config_path: .envctl.toml} all }
export def run [
    cli:     record
    profile: string   # "envfile" | "secrets" | "certs" | "all"
]: nothing -> record {
    if not (is-valid-profile $profile) {
        error make {
            msg: $"[pipeline] unknown profile '($profile)' — expected: envfile, secrets, certs, all"
        }
    }

    let rt = (init-runtime $cli $profile)
    let rt = (compile-phase $rt)
    execute-phase $rt

    $rt
}

# Compile only — no execute, no lock write, no state append.
# Used by: diff, dry-run, health checks, certs status.
@example "Compile envfile pipeline" { compile {stage: dev, config_path: .envctl.toml} envfile }
@example "Compile certs pipeline"   { compile {stage: dev, config_path: .envctl.toml} certs }
export def compile [cli: record, profile: string] {
    if not (is-valid-profile $profile) {
        error make {
            msg: $"[pipeline] unknown profile '($profile)'"
        }
    }

    let rt = (init-runtime $cli $profile)
    compile-phase $rt
}

# ---------------------------------------------------------------------------
# Pipeline phases
# ---------------------------------------------------------------------------

def init-runtime [cli: record, profile: string] {
    let ctx = (build-ctx $cli)
    let manifests = (load-providers $ctx.ast)
    let providers_by_name = ($manifests | reduce --fold {} {|m, acc|
        $acc | insert $m.name $m
    })

    let backends = (list-backends | each {|name| load-backend $name })
    let lock = (read-lock)

    check-versions $manifests $backends $lock
    log detail --ns pipeline $"profile: ($profile) | stage: ($ctx.stage)"

    {
        ctx: $ctx
        manifests: $manifests
        providers: $providers_by_name
        profile: $profile
    }
}

def compile-phase [rt: record] {
    let ast = $rt.ctx.ast
    let sub_ast = match $rt.profile {
        "envfile" => (envfile project $ast)
        "secrets" => (secrets project $ast)
        "certs" => (certs project $ast)
        "all" => $ast
    }

    let validated = (validator validate $sub_ast $rt.providers)
    let plan = (plan build $rt.ctx $validated $rt.profile $rt.providers)
    $rt | insert sub_ast $validated | insert plan $plan
}

def execute-phase [rt: record] {
    let ctx_with_providers = ($rt.ctx | upsert providers $rt.providers)
    executor apply $rt.plan $ctx_with_providers

    if not $rt.ctx.dry_run {
        let backends = (load-plan-backends $rt.plan)
        write-lock $rt.plan $rt.manifests $backends
        append-entry $"($rt.profile) generate" $rt.ctx.stage $rt.profile false
        log detail --ns pipeline "lock updated, state appended"
    }
}
