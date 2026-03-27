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
    mut ctx_mut = ($ctx | upsert completed_certs {})
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
    # Use reduce so each resolved value is available to subsequent lines.
    # e.g. SECRETS_DIR=/run/secrets followed by FILE={{SECRETS_DIR}}/pass resolves correctly.
    let acc = (
        $content | lines | reduce --fold {
            lines: []
            env_vars: ($ctx | get --optional env_vars | default {})
        } { |line, acc|
            let trimmed = ($line | str trim)

            if ($trimmed | is-empty) or ($trimmed | str starts-with "#") {
                {
                    lines: ($acc.lines | append $line), env_vars: $acc.env_vars
                }
            } else {
                let parts = ($line | split row "=" | collect)
                let key   = ($parts | first | str trim)
                let val   = ($parts | skip 1 | str join "=")

                if ($key | is-empty) or ($key in $excluded) {
                    {
                        lines: ($acc.lines | append $line), env_vars: $acc.env_vars
                    }
                } else {
                    let run_ctx  = ($ctx | upsert env_vars $acc.env_vars)
                    let resolved = try { resolve $val $run_ctx } catch { $val }

                    {
                        lines:    ($acc.lines | append $"($key)=($resolved)")
                        env_vars: ($acc.env_vars | upsert $key $resolved)
                    }
                }
            }
        }
    )
    $acc.lines | str join "\n"
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
    let resolve_ctx = {
        env_vars: ($ctx | get --optional env_vars | default {})
        secrets_root: ($ctx | get --optional secrets_root | default .)
        providers: ($ctx | get --optional providers | default {})
        cfg: ($ctx | get --optional cfg | default {})
        cli: ($ctx | get --optional cli | default {})
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
