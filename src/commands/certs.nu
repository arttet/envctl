# ==============================================================================
# commands/certs.nu — Certificate lifecycle management.
#
# All orchestration delegated to runtime/pipeline.nu (profile=certs).
#
# Commands:
#   envctl certs generate           — generate all certs from [certs.*]
#   envctl certs generate --name X  — generate one cert by name
#   envctl certs rotate --name X    — overwrite + backup one cert
#   envctl certs rotate-all         — overwrite + backup all certs
#   envctl certs status             — show expiry and health for all certs
# ==============================================================================

use ../runtime/pipeline.nu [compile, run]
use ../runtime/backends/dispatch.nu [dispatch-health]
use ../engine/plan.nu [set-rotate-mode, set-rotate-one]
use ../engine/executor.nu [apply]
use ../state/state.nu [append-entry]
use ../core/log.nu

# Generate all certificates declared in [certs.*].
#
# Respects mode = create-only — skips existing certs.
# external = true certs are read from backend, never generated.
@example "Generate all certs"       { envctl certs generate }
@example "Generate all certs prod"  { envctl certs generate --stage prod }
@example "Generate one cert"        { envctl certs generate --name root }
@example "Dry-run cert generation"  { envctl certs generate --dry-run }
export def "envctl certs generate" [
    --name:   string   # Generate only this cert (by name in [certs.*])
    --stage:  string   # Active stage
    --dry-run          # Print what would happen, no writes
    --quiet            # Suppress informational output
    --config: string   # Override config path
]: nothing -> nothing {
    if $quiet {
        log set-quiet true
    }

    let cli = (make-cli $config $stage $dry_run $quiet)
    let rt = (compile $cli "certs")
    let plan = if ($name | is-empty) {
        $rt.plan
    } else {
        $rt.plan | filter-plan-by-name $name
    }

    if ($plan.actions | is-empty) {
        let msg = if ($name | is-empty) { "no certs declared in [certs.*]" } else { $"cert '($name)' not found in [certs.*]" }
        log warn --ns "certs" $msg
        return
    }

    if $rt.ctx.dry_run {
        log info --ns "certs" "[dry-run] would generate:"
        for action in $plan.actions { log-action-line $action }
        return
    }

    let ctx_with_providers = ($rt.ctx | upsert providers $rt.providers)
    apply $plan $ctx_with_providers | ignore
    append-entry "certs generate" $rt.ctx.stage "certs" false

    log success --ns "certs" "done"
}

# Overwrite and backup a single certificate by name.
#
# Works only on write-cert actions — external certs cannot be rotated.
@example "Rotate one cert"       { envctl certs rotate --name app }
@example "Rotate one cert prod"  { envctl certs rotate --name app --stage prod }
export def "envctl certs rotate" [
    --name:   string   # Cert name as declared in [certs.NAME]
    --stage:  string   # Active stage
    --dry-run          # Print what would happen, no writes
    --quiet            # Suppress informational output
    --config: string   # Override config path
]: nothing -> nothing {
    if $quiet {
        log set-quiet true
    }

    if ($name | is-empty) {
        log error --ns "certs" "--name is required"
        return
    }

    let cli = (make-cli $config $stage $dry_run $quiet)
    let rt = (compile $cli "certs")

    # Verify name exists and is a write-cert (not external)
    let target_action = ($rt.plan.actions | where kind == "write-cert" and name == $name | get 0?)
    if $target_action == null {
        let is_external = ($rt.plan.actions | where kind == "read-cert" and name == $name | is-not-empty)
        if $is_external { log error --ns "certs" $"'($name)' is external = true — cannot rotate, manage it externally" } else { log error --ns "certs" $"'($name)' not found in [certs.*]" }
        return
    }

    # Full chain must run in order — rotate only sets overwrite on target
    let plan = (set-rotate-one $rt.plan $name)
    if $rt.ctx.dry_run {
        log info --ns "certs" $"[dry-run] would rotate: ($name)"
        return
    }

    let ctx_with_providers = ($rt.ctx | upsert providers $rt.providers)
    apply $plan $ctx_with_providers | ignore
    append-entry $"certs rotate ($name)" $rt.ctx.stage "certs" false
    log success --ns "certs" $"rotated: ($name)"
}

# Overwrite and backup all non-external certificates.
@example "Rotate all certs"      { envctl certs rotate-all }
@example "Rotate all certs prod" { envctl certs rotate-all --stage prod }
export def "envctl certs rotate-all" [
    --stage:  string   # Active stage
    --dry-run          # Print what would happen, no writes
    --quiet            # Suppress informational output
    --config: string   # Override config path
]: nothing -> nothing {
    if $quiet {
        log set-quiet true
    }

    let cli = (make-cli $config $stage $dry_run $quiet)
    let rt = (compile $cli "certs")

    let write_actions = ($rt.plan.actions | where kind == "write-cert")
    if ($write_actions | is-empty) {
        log warn --ns "certs" "no generated certs declared in [certs.*]"
        return
    }

    let plan = ($rt.plan | set-rotate-mode)

    if $rt.ctx.dry_run {
        log info --ns "certs" "[dry-run] would rotate all certs:"
        for action in $write_actions {
            log detail --ns "certs" $"  ($action.name) → ($action.backend)"
        }

        return
    }

    let ctx_with_providers = ($rt.ctx | upsert providers $rt.providers)
    apply $plan $ctx_with_providers | ignore
    append-entry "certs rotate-all" $rt.ctx.stage "certs" false
    log success --ns "certs" "all certs rotated"
}

# Show health and expiry for all certs declared in [certs.*].
#
# Reads from backend health_fn — never throws on missing cert.
@example "Show cert status"      { envctl certs status }
@example "Show cert status prod" { envctl certs status --stage prod }
export def "envctl certs status" [
    --stage:  string   # Active stage
    --quiet            # Suppress informational output
    --config: string   # Override config path
]: nothing -> nothing {
    if $quiet {
        log set-quiet true
    }

    let cli = (make-cli $config $stage false $quiet)
    let rt = (compile $cli "certs")

    let cert_actions = ($rt.plan.actions | where kind in ["write-cert", "read-cert"])
    if ($cert_actions | is-empty) {
        log warn --ns "certs" "no certs declared in [certs.*]"
        return
    }

    let ctx_with_providers = ($rt.ctx | upsert providers $rt.providers)
    log info --ns "certs" $"($cert_actions | length) cert\(s\):"

    for action in $cert_actions {
        let health = (dispatch-health $action.backend $ctx_with_providers $action.name $action.options)
        let icon = if $health.ok { "✓" } else { "✗" }
        let ext_label = if $action.kind == "read-cert" { " [external]" } else { "" }
        log info --ns "certs" $"  ($icon) ($action.name)($ext_label) — ($health.info)"
    }
}

def make-cli [
    config
    stage
    dry_run: bool
    quiet: bool
] {
    {
        config_path: ($config | default $env.ENVCTL_CONFIG)
        stage: ($stage | default $env.ENVCTL_STAGE)
        dry_run: ($dry_run or ($env.ENVCTL_DRY_RUN? == "true"))
        quiet: $quiet
    }
}

# Filter plan to a single cert by name — keeps all read-cert actions (signers needed).
def filter-plan-by-name [name: string] {
    let plan = $in
    # Keep read-cert actions (signers) + write-cert actions up to and including target (topo order preserved)
    let target_idx = (
        $plan.actions | enumerate | where item.kind == "write-cert" and item.name == $name | get 0? | get index?
    )

    if $target_idx == null {
        return ($plan | upsert actions [])
    }

    let filtered = (
        $plan.actions | enumerate | where index <= $target_idx or item.kind == "read-cert" | get item
    )
    $plan | upsert actions $filtered
}

def log-action-line [action: record] {
    match $action.kind {
        "read-cert" => { log detail --ns "certs" $"  [external] ($action.name) from ($action.backend)" }
        "write-cert" => {
            let signed_by = ($action | get --optional signed_by | default "")
            let signer = if ($signed_by | is-empty) { "self-signed" } else { $"signed by ($signed_by)" }
            log detail --ns "certs" $"  ($action.name) ($signer) → ($action.backend)"
        }
        _ => { }
    }
}
