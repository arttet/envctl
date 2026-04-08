# ==============================================================================
# engine/executor.nu — ExecutionPlan applier.
#
# ONLY layer with side effects — all other engine layers are pure.
#
# Action dispatch:
#   write-env    → render .env from template + resolved generators
#   write-secret → generate value via provider → write via backend
#   read-cert    → read cert+key PEM from backend → store in completed_certs
#   write-cert   → read signer from completed_certs → generate in memory → write via backend
#
# Cert execution order (guaranteed by topo-sort in parser.nu):
#   1. read-cert (external = true)  → completed_certs["name"] = { cert, key }
#   2. write-cert signed_by empty   → generate root CA → completed_certs["name"] = { cert, key }
#   3. write-cert signed_by = "X"   → read completed_certs["X"] → generate → completed_certs["name"]
# ==============================================================================

use ../language/grammar.nu [resolve]
use ../runtime/backends/dispatch.nu [dispatch-write, dispatch-read, dispatch-exists, dispatch-health]
use ../core/backup.nu [backup-file]
use ../core/constants.nu [DEFAULT_BAK_DIR]
use ../core/log.nu

@example "Apply empty plan" { apply { profile: envfile dry_run: false generators: {} actions: [] } { env_vars: {} secrets_root: . providers: {} cfg: {} cli: {} } }
export def apply [plan: record, ctx: record] {
    if $plan.dry_run {
        log-dry-run $plan
        return
    }

    # completed_certs accumulates PEM strings as certs are read or generated
    # { name → { cert: string, key: string } }
    # secrets_paths maps secret key → resolved host file path for {{ secret:IDENT }} resolution
    let secrets_paths = (
        $plan.actions
        | where kind == "write-secret"
        | reduce --fold {} {|a, acc|
            let path = ($a.options | get --optional path | default "")
            if ($path | is-not-empty) {
                $acc | insert $a.key $path
            } else {
                $acc
            }
        }
    )
    mut ctx_mut = ($ctx | upsert completed_certs {} | upsert secrets_paths $secrets_paths)
    for action in $plan.actions {
        match $action.kind {
            "write-env" => {
                apply-write-env $action $plan $ctx_mut
            }
            "write-secret" => {
                apply-write-secret $action $ctx_mut
            }
            "read-cert" => {
                let pem = (apply-read-cert $action $ctx_mut)
                $ctx_mut = ($ctx_mut | upsert completed_certs ($ctx_mut.completed_certs | insert $action.name $pem))
            }
            "write-cert" => {
                let pem = (apply-write-cert $action $ctx_mut)
                $ctx_mut = ($ctx_mut | upsert completed_certs ($ctx_mut.completed_certs | insert $action.name $pem))
            }
            _ => {
                log warn --ns executor $"unknown action kind: ($action.kind) — skipping"
            }
        }
    }
}

def apply-write-env [action: record, plan: record, ctx: record] {
    let pattern = $action.pattern
    let env_file = $action.file
    if not ($pattern | path exists) {
        log warn --ns executor $"template not found: ($pattern) — skipping envfile"
        return
    }

    let template_content = (open --raw $pattern)
    let resolve_ctx = {
        env_vars: $plan.generators
        secrets_root: ($ctx | get --optional secrets_root | default .)
        providers: ($ctx | get --optional providers | default {})
        cfg: ($ctx | get --optional cfg | default {})
        cli: ($ctx | get --optional cli | default {})
        stage: ($ctx | get --optional stage | default "dev")
        secrets_paths: ($ctx | get --optional secrets_paths | default {})
    }

    let rendered = (render-env $template_content $resolve_ctx ...$action.excluded)
    let bk = (backup-file $env_file --dir $DEFAULT_BAK_DIR)
    if $bk != null {
        log detail --ns executor $"backup: ($bk)"
    }

    $rendered | save --force $env_file
    log success --ns executor $"wrote ($env_file)"
}

def render-env [content: string, ctx: record, ...excluded: string] {
    let lines      = ($content | lines)
    let base_vars  = ($ctx | get --optional env_vars | default {})

    # Phase 1 — multi-pass resolution to handle forward references.
    # Each pass feeds newly resolved values back into env_vars so that a variable
    # defined later in the file can satisfy a token that appeared earlier.
    # Mirrors resolve-generators in plan.nu — runs until stable or 10 passes.
    mut env_vars = $base_vars
    mut passes   = 0

    loop {
        if $passes >= 10 { break }
        let prev = $env_vars

        $env_vars = ($lines | reduce --fold $env_vars {|line, acc|
            let trimmed = ($line | str trim)
            if ($trimmed | is-empty) or ($trimmed | str starts-with "#") {
                $acc
            } else {
                let parts = ($line | split row "=" | collect)
                let key   = ($parts | first | str trim)
                let val   = ($parts | skip 1 | str join "=")
                if ($key | is-empty) or ($key in $excluded) {
                    $acc
                } else {
                    let current = ($acc | get --optional $key | default "")
                    if ($current | is-not-empty) and not ($current | str contains "{{") {
                        $acc
                    } else {
                        let resolved = try { resolve $val ($ctx | upsert env_vars $acc) } catch { $val }
                        $acc | upsert $key $resolved
                    }
                }
            }
        })

        if $env_vars == $prev { break }
        $passes += 1
    }

    # Phase 2 — render output lines in original order using the fully resolved env_vars.
    # Assign to immutable binding — Nushell disallows capturing mut vars in closures.
    let resolved_vars = $env_vars
    $lines | each {|line|
        let trimmed = ($line | str trim)
        if ($trimmed | is-empty) or ($trimmed | str starts-with "#") {
            $line
        } else {
            let parts = ($line | split row "=" | collect)
            let key   = ($parts | first | str trim)
            let val   = ($parts | skip 1 | str join "=")
            if ($key | is-empty) or ($key in $excluded) {
                $line
            } else {
                let current = ($resolved_vars | get --optional $key | default "")
                let resolved = if ($current | is-not-empty) and not ($current | str contains "{{") {
                    $current
                } else {
                    try { resolve $val ($ctx | upsert env_vars $resolved_vars) } catch { $val }
                }
                $"($key)=($resolved)"
            }
        }
    } | str join "\n"
}

def apply-write-secret [action: record, ctx: record] {
    let exists = (dispatch-exists $action.backend $ctx $action.key $action.options)
    if $exists and $action.mode == create-only {
        log detail --ns executor $"exists, skipping: ($action.key)"
        return
    }

    if $exists and $action.backup {
        let path = ($action.options | get --optional path | default "")
        if ($path | is-not-empty) {
            let bk = (backup-file $path)
            if $bk != null {
                log detail --ns executor $"backup: ($bk)"
            }
        }
    }

    let value = (resolve-secret-value $action $ctx)
    dispatch-write $action.backend $ctx $action.key $value $action.options

    log success --ns executor $"wrote secret: ($action.key)"
}

def resolve-secret-value [action: record, ctx: record] {
    let provider_overrides = ($action | get --optional provider_options | default {})

    # Merge per-secret provider_options into ctx.cfg.providers.{name}, shadowing global config.
    # Provider name is read from src_tokens (type == "provider").
    let merged_cfg = if ($provider_overrides | is-empty) {
        ($ctx | get --optional cfg | default {})
    } else {
        let src_tokens  = ($action | get --optional src_tokens | default [])
        let prov_tokens = ($src_tokens | where type == provider)
        let prov_name   = if ($prov_tokens | is-empty) {
            ""
        } else {
            $prov_tokens | first | get --optional name | default ""
        }

        let base_cfg_raw     = ($ctx          | get --optional cfg       | default {})
        let base_prov_cfg    = ($base_cfg_raw  | get --optional providers | default {})
        let base_named_cfg   = ($base_prov_cfg | get --optional $prov_name | default {})
        let merged_named_cfg = ($base_named_cfg | merge $provider_overrides)
        let merged_prov_cfg  = ($base_prov_cfg  | upsert $prov_name $merged_named_cfg)
        $base_cfg_raw | upsert providers $merged_prov_cfg
    }

    let resolve_ctx = {
        env_vars:      ($ctx | get --optional env_vars      | default {})
        secrets_root:  ($ctx | get --optional secrets_root  | default .)
        providers:     ($ctx | get --optional providers     | default {})
        cfg:           $merged_cfg
        cli:           ($ctx | get --optional cli           | default {})
        secrets_paths: ($ctx | get --optional secrets_paths | default {})
    }

    try {
        resolve $action.value_source $resolve_ctx
    } catch {|err|
        error make { msg: $"[executor] failed to resolve value_source for '($action.key)': ($err.msg)" }
    }
}

# Read cert+key PEM from backend — never generates, never writes.
# Returns { cert: string, key: string } for completed_certs.
def apply-read-cert [action: record, ctx: record] {
    log detail --ns executor $"reading external cert: ($action.name) from ($action.backend)"

    let pem = (dispatch-read $action.backend $ctx $action.name $action.options)
    if ($pem | describe) != record {
        error make { msg: $"[executor] read-cert '($action.name)': backend did not return a cert pair record" }
    }

    if ($pem | get --optional cert | default "" | is-empty) {
        error make { msg: $"[executor] read-cert '($action.name)': cert PEM is empty" }
    }

    if ($pem | get --optional key | default "" | is-empty) {
        error make { msg: $"[executor] read-cert '($action.name)': key PEM is empty" }
    }

    log success --ns executor $"loaded external cert: ($action.name)"

    $pem
}

# Generate cert+key in memory via certs provider, write via backend.
# Returns { cert: string, key: string } PEM for completed_certs.
def apply-write-cert [action: record, ctx: record] {

    let exists = (dispatch-exists $action.backend $ctx $action.name $action.options)
    if $exists and $action.mode == create-only {
        log detail --ns executor $"exists, skipping cert: ($action.name)"
        # Still need to return PEM so downstream certs can use this as signer
        return (dispatch-read $action.backend $ctx $action.name $action.options)
    }

    if $exists and $action.backup {
        let cert_path = ($action.options | get --optional cert | default "")
        let key_path = ($action.options | get --optional key | default "")
        if ($cert_path | is-not-empty) { backup-file $cert_path }
        if ($key_path | is-not-empty) { backup-file $key_path }
    }

    # Find certs provider manifest
    let certs_manifest = (
        $ctx | get --optional providers | default {} | get --optional certs
    )

    if $certs_manifest == null {
        error make {msg: "[executor] 'certs' provider not loaded — add 'certs' to providers.enabled"} }

    let generate_fn = ($certs_manifest.resolve | get --optional "generate-cert")
    if $generate_fn == null { error make {msg: "[executor] certs manifest missing 'generate-cert' in resolve"} }
    # Inject action into ctx — certs provider reads it
    let cert_ctx = ($ctx | upsert current_cert_action $action)
    # Generate in memory → { cert: string, key: string }
    let pem = (do $generate_fn $cert_ctx)
    # Write via backend
    dispatch-write $action.backend $ctx $action.name $pem $action.options
    log success --ns executor $"wrote cert: ($action.name)"
    $pem
}
def log-dry-run [plan: record] {
    log info --ns executor $"[dry-run] profile: ($plan.profile)"
    log info --ns executor $"[dry-run] ($plan.actions | length) action\(s\):"
    for action in $plan.actions { match $action.kind {
        "write-env" => { log detail --ns executor $"  write-env    → ($action.file)" }
        "write-secret" => { log detail --ns executor $"  write-secret → ($action.key) via ($action.backend)" }
        "read-cert" => { log detail --ns executor $"  read-cert    → ($action.name) from ($action.backend)" }
        "write-cert" => {
            let signed_by = ($action | get --optional signed_by | default "")
            let signer = if ($signed_by | is-empty) { "self-signed" } else { $"signed by ($signed_by)" }
            log detail --ns executor $"  write-cert   → ($action.name) \(($signer)\) via ($action.backend)"
        }
        _ => { log detail --ns executor $"  ($action.kind)" }
    } }
}
