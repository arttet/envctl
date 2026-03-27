# ==============================================================================
# runtime/backends/dispatch.nu — Backend dispatch.
#
# Thin layer between executor and backend plugins.
# Routes write/read/exists/health calls to the correct backend manifest fn.
# executor.nu calls dispatch — never imports plugins directly.
# ==============================================================================

use ./registry.nu [load-backend]
use ../../language/grammar.nu [resolve]

use ../../core/log.nu

# Write a secret or cert pair to a backend.
@example "Dispatch write to file backend" { dispatch-write file { env_vars: {} secrets_root: . providers: {} cfg: {} cli: {} } MY_SECRET value {path: secrets/my_secret} }
export def dispatch-write [
    backend: string
    ctx: record
    var: string
    value
    options: record
] {
    let m = (load-backend $backend)
    let write_fn = ($m | get --optional write_fn)

    if $write_fn == null {
        error make {
            msg: $"[dispatch] backend '($backend)' missing write_fn in manifest"
        }
    }

    null | do $write_fn $ctx $var $value $options
}

# Read a secret or cert pair from a backend.
# Returns string for single secrets, { cert, key } for cert pairs.
@example "Dispatch read from file backend" { dispatch-read file { env_vars: {} secrets_root: . providers: {} cfg: {} cli: {} } MY_CERT { cert: secrets/my.crt, key: secrets/my.key } }
export def dispatch-read [
    backend: string
    ctx: record
    var: string
    options: record
] {
    let m = (load-backend $backend)
    let read_fn = ($m | get --optional read_fn)
    if $read_fn == null {
        error make {
            msg: $"[dispatch] backend '($backend)' missing read_fn — cannot read '($var)'"
        }
    }
    null | do $read_fn $ctx $var $options
}

# Check if a secret exists in a backend.
# Returns false if backend does not implement exists_fn.
@example "Dispatch exists check to file backend" { dispatch-exists file { env_vars: {} secrets_root: . providers: {} cfg: {} cli: {} } MY_SECRET {path: secrets/my_secret} }
export def dispatch-exists [
    backend: string
    ctx: record
    var: string
    options: record
] {
    let m = (load-backend $backend)
    let exists_fn = ($m | get --optional exists_fn)
    if $exists_fn == null {
        log detail --ns dispatch $"backend '($backend)' has no exists_fn — assuming not exists"
        return false
    }

    null | do $exists_fn $ctx $var $options
}

# Resolve any remaining {{ }} tokens in an options record using the full ctx.
# Called before dispatch-health so plugins receive fully resolved option values
# even when plan-time generator resolution partially failed.
def resolve-options [options: record, ctx: record] {
    let resolve_ctx = {
        env_vars: ($ctx | get --optional env_vars | default {})
        secrets_root: ($ctx | get --optional secrets_root | default ".")
        providers: ($ctx | get --optional providers | default {})
        cfg: ($ctx | get --optional cfg | default {})
        cli: ($ctx | get --optional cli | default {})
    }

    $options | columns | reduce --fold $options {|key, acc|
        let val = ($acc | get --optional $key | default "")
        if (($val | describe) == "string") and ($val | str contains "{{") {
            $acc | upsert $key (try { resolve $val $resolve_ctx } catch { $val })
        } else {
            $acc
        }
    }
}

# Run health check for a secret in a backend.
# Never throws — always returns { ok: bool, info: string }.
@example "Dispatch health check to file backend" { dispatch-health file { env_vars: {} secrets_root: . providers: {} cfg: {} cli: {} } MY_SECRET { path: secrets/my_secret } }
export def dispatch-health [
    backend: string
    ctx: record
    var: string
    options: record
] {
    let m = (load-backend $backend)
    let health_fn = ($m | get --optional health_fn)
    if $health_fn == null {
        return {
            ok: true
            info: $"backend '($backend)' has no health_fn"
        }
    }

    let resolved_opts = (resolve-options $options $ctx)
    try {
        null | do $health_fn $ctx $var $resolved_opts
    } catch {
        |err| {
            ok: false
            info: $"[dispatch] health_fn threw: ($err.msg)"
        }
    }
}
