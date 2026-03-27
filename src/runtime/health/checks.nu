# ==============================================================================
# runtime/health/checks.nu — Primitive health check functions.
#
# Check types: tool, file, cert_expiry, secret_age
# Each function returns { ok: bool, info: string } — never throws.
# ==============================================================================

# Check whether an external tool is available in PATH.
@example "Check existing tool"  { check-tool nu }
@example "Check missing tool"   { check-tool nonexistent-tool-xyz }
export def check-tool [name: string] {
    let ok = (which $name | is-not-empty)
    if $ok {
        {
            ok: true
            info: $"($name) found"
        }
    } else {
        {
            ok: false
            info: $"($name) not found in PATH"
        }
    }
}

# Check whether a file exists on disk.
@example "Check existing file"  { check-file .envctl.toml }
@example "Check missing file"   { check-file .nonexistent-file }
export def check-file [path: string] {
    if ($path | path exists) {
        {
            ok: true
            info: $"exists: ($path)"
        }
    } else {
        {
            ok: false
            info: $"missing: ($path)"
        }
    }
}

# Check certificate expiry from a PEM file via openssl.
# Returns ok:false if cert is missing, unreadable, or expires within warn_days.
@example "Check cert expiry default threshold" { check-cert-expiry secrets/cert.pem }
@example "Check cert expiry 7 days"            { check-cert-expiry secrets/cert.pem 7 }
export def check-cert-expiry [path: string, warn_days: int = 30] {
    if not ($path | path exists) {
        return {
            ok: false
            info: $"cert not found: ($path)"
        }
    }

    try {
        let threshold = ($warn_days * 86400)
        let out = (openssl x509 -checkend $threshold -noout -in $path | complete)

        if $out.exit_code == 0 {
            {
                ok: true
                info: $"valid for at least ($warn_days) days"
            }
        } else {
            {
                ok: false
                info: $"expires within ($warn_days) days"
            }
        }
    } catch {|err|
        {
            ok: false
            info: $"cert check error: ($err.msg)"
        }
    }
}

# Check secret file age by mtime. Returns ok:false if older than max_days.
@example "Check secret age default max"  { check-secret-age "secrets/password" }
@example "Check secret age 90 days max" { check-secret-age "secrets/password" 90 }
export def check-secret-age [path: string, max_days: int = 365] {
    if not ($path | path exists) {
        return {
            ok: false
            info: $"secret not found: ($path)"
        }
    }

    try {
        let modified = (ls $path | get modified | first)
        let age_days = (((date now) - $modified) / 1day | math floor)
        if $age_days > $max_days {
            {
                ok: false
                info: $"($age_days) days old \(max: ($max_days)\)"
            }
        } else {
            {
                ok: true
                info: $"($age_days) days old"
            }
        }
    } catch {
        {
            ok: true,
            info: "age unknown"
        }
    }
}
