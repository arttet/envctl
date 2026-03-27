# ==============================================================================
# plugins/backends/file.nu — File system backend.
#
# write_fn value contract:
#   string          → write single file at options.path
#   { cert, key }   → write cert file at options.cert, key file at options.key
#
# read_fn return contract:
#   options.cert + options.key present → { cert: string, key: string }
#   options.path present               → string
#
# No imports from src/ — plugin is self-contained.
# ==============================================================================

export def manifest []: nothing -> record {
    {
        name:          "file"
        version:       "1.0.0"
        kind:          "backend"
        provides:      [write-secret exists-secret health-secret read-secret]
        config_schema: "file.config.schema.toml"
        health_schema: "file.health.schema.toml"
        read_fn:       {|ctx, var, options| read-secret $ctx $var $options }
        write_fn:      {|ctx, var, value, options| write-secret $ctx $var $value $options }
        exists_fn:     {|ctx, var, options| exists-secret $ctx $var $options }
        health_fn:     {|ctx, var, options| health-secret $ctx $var $options }
    }
}

# Read a secret or cert pair from disk.
# Returns { cert: string, key: string } for cert pairs, string for single files.
export def read-secret [
    ctx:     record
    var:     string
    options: record
] {
    let cert_path = ($options | get --optional cert | default "")
    let key_path  = ($options | get --optional key  | default "")

    if ($cert_path | is-not-empty) and ($key_path | is-not-empty) {
        if not ($cert_path | path exists) {
            error make { msg: $"[file] cert not found: ($cert_path) — run: envctl certs generate --name ($var)" }
        }
        if not ($key_path | path exists) {
            error make { msg: $"[file] key not found: ($key_path) — run: envctl certs generate --name ($var)" }
        }
        return {
            cert: (open --raw $cert_path)
            key:  (open --raw $key_path)
        }
    }

    let path = (resolve-path $ctx $var $options)
    if not ($path | path exists) {
        error make { msg: $"[file] secret not found: ($path)" }
    }
    open --raw $path
}

export def write-secret [
    ctx:     record
    var:     string
    value:   any
    options: record
] {
    let value_type = ($value | describe)

    if ($value_type | str starts-with "record") {
        write-cert-pair $ctx $var $value $options
    } else {
        write-single $ctx $var ($value | into string) $options
    }
}

def write-single [
    ctx:     record
    var:     string
    value:   string
    options: record
]: nothing -> nothing {
    let path = (resolve-path $ctx $var $options)
    ensure-parent $path
    $value | save --force $path
}

def write-cert-pair [
    ctx:     record
    var:     string
    pem:     record
    options: record
]: nothing -> nothing {
    let cert_path = ($options | get --optional cert | default "")
    let key_path  = ($options | get --optional key  | default "")

    if ($cert_path | is-empty) {
        error make { msg: $"[file] options.cert is required for cert pair '($var)'" }
    }
    if ($key_path | is-empty) {
        error make { msg: $"[file] options.key is required for cert pair '($var)'" }
    }

    ensure-parent $cert_path
    ensure-parent $key_path

    $pem.cert | save --force $cert_path
    $pem.key  | save --force $key_path
}

export def exists-secret [
    ctx:     record
    var:     string
    options: record
] {
    let cert_path = ($options | get --optional cert | default "")
    let key_path  = ($options | get --optional key  | default "")

    if ($cert_path | is-not-empty) and ($key_path | is-not-empty) {
        return (
            ($cert_path | path exists) and
            ((open --raw $cert_path | is-not-empty)) and
            ($key_path  | path exists) and
            ((open --raw $key_path | is-not-empty))
        )
    }

    let path = (resolve-path $ctx $var $options)
    ($path | path exists) and ((open --raw $path | is-not-empty))
}

export def health-secret [
    ctx:     record
    var:     string
    options: record
] {
    let cert_path = ($options | get --optional cert | default "")
    let key_path  = ($options | get --optional key  | default "")

    if ($cert_path | is-not-empty) and ($key_path | is-not-empty) {
        return (cert-pair-health $var $cert_path $key_path)
    }

    single-file-health $var (resolve-path $ctx $var $options)
}

def cert-pair-health [var: string, cert_path: string, key_path: string] {
    if not ($cert_path | path exists) {
        return { ok: false, info: $"cert missing: ($cert_path)" }
    }
    if not ($key_path | path exists) {
        return { ok: false, info: $"key missing: ($key_path)" }
    }

    let expiry_result = (openssl x509 -enddate -noout -in $cert_path | complete)
    if $expiry_result.exit_code != 0 {
        return { ok: false, info: $"invalid cert: ($cert_path)" }
    }

    let expiry_str  = ($expiry_result.stdout | str trim | str replace "notAfter=" "")
    let expiry_date = (try { $expiry_str | into datetime } catch { null })

    if $expiry_date == null {
        return { ok: true, info: "cert exists, expiry unknown" }
    }

    let days_left = ((($expiry_date - (date now)) / 1day) | math floor)

    let status = match $days_left {
        _ if $days_left < 0  => "EXPIRED"
        _ if $days_left < 7  => "CRITICAL"
        _ if $days_left < 30 => "WARNING"
        _                    => "OK"
    }

    {
        ok:         ($days_left >= 0)
        info:       $"($status) — ($days_left) days left \(expires ($expiry_str)\)"
        days_left:  $days_left
        expires_at: $expiry_str
    }
}

def single-file-health [var: string, path: string] {
    if not ($path | path exists) {
        return { ok: false, info: $"missing: ($path)" }
    }

    if (open --raw $path | is-empty) {
        return { ok: false, info: $"empty: ($path)" }
    }

    { ok: true, info: "exists" }
}

def resolve-path [ctx: record, var: string, options: record] {
    let explicit = ($options | get --optional path | default "")
    if ($explicit | is-not-empty) {
        let secrets_root = ($ctx | get --optional secrets_root | default ".")
        let secrets_abs = ($secrets_root | path expand)
        let target_abs = ($explicit | path expand)

        # Simple path traversal check
        if not ($target_abs | str starts-with $secrets_abs) {
            error make { msg: $"[file] path traversal detected: ($explicit) escapes secrets root ($secrets_root)" }
        }

        return $target_abs
    }

    let secrets_root = ($ctx | get --optional secrets_root | default ".")
    $secrets_root | path join $var
}

def ensure-parent [path: string]: nothing -> nothing {
    let parent = ($path | path dirname)
    if ($parent | is-not-empty) and not ($parent | path exists) {
        mkdir $parent
    }
}
