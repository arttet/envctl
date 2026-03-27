# ==============================================================================
# state/lock.nu — Lock file management.
#
# .envctl.lock — committed to git, tracks provider/backend versions only.
# Strict policy: if manifest version != lock version → hard error.
#
# Lock format (TOML):
#   [providers.NAME]
#   version = "1.0.0"
#
#   [backends.NAME]
#   version = "1.0.0"
#
# Updated only in execute-phase, never on dry-run.
# Each pipeline (envfile/secrets) updates only its relevant sections.
# ==============================================================================

use ../core/constants.nu [DEFAULT_LOCK_PATH]
use ../core/log.nu

# Read .envctl.lock from disk.
# Returns empty record if file does not exist.
@example "Read lock from default path" { read-lock ".envctl.lock" }
@example "Read missing lock — returns empty" { read-lock ".envctl.missing.lock" }
export def read-lock [path?: string] {
    let p = ($path | default $DEFAULT_LOCK_PATH)
    if not ($p | path exists) {
        return {}
    }

    try {
        open $p | from toml
    } catch {|err|
        error make {
            msg: $"[lock] failed to parse ($p): ($err.msg)"
        }
    }
}

# Write provider and backend versions to lock file.
# Only updates sections relevant to the given profile.
# Never call on dry-run — enforced by pipeline.nu.
@example "Write lock for envfile profile" { write-lock {profile: envfile, generators: {}, actions: [] } [ { name: git, version: 1.0.0 } ] [] ".envctl.lock" }
@example "Write lock for secrets profile" { write-lock {profile: secrets, generators: {}, actions: []} [ { name: password, version: 1.0.0 } ] [ { name: file, version: 1.0.0 } ] ".envctl.lock" }
export def write-lock [
    plan:      record          # ExecutionPlan — used for profile
    manifests: list<record>    # loaded provider manifests
    backends:  list<record>    # loaded backend manifests
    path:      string = $DEFAULT_LOCK_PATH
]: nothing -> nothing {

    let existing = (read-lock $path)

    # Build providers section from manifests
    let providers_section = ($manifests | reduce --fold {} {|m, acc|
        $acc | insert $m.name {version: $m.version}
    })

    # Build backends section from backend manifests
    let backends_section = ($backends | reduce --fold {} {|b, acc|
        $acc | insert $b.name {version: $b.version}
    })

    let existing_providers = ($existing | get --optional providers | default {})
    let existing_backends = ($existing | get --optional backends | default {})
    let new_lock = {
        providers: ($existing_providers | merge $providers_section)
        backends: ($existing_backends | merge $backends_section)
    }
    $new_lock | to toml | save --force $path

    log detail --ns lock $"written: ($path)"
}

# Strict version check — hard error if any manifest version != lock version.
# Called at pipeline init before compile phase.
@example "Check lock versions — empty lock passes" { check-versions [] [] {} }
export def check-versions [
    manifests: list<record>    # loaded provider manifests
    backends:  list<record>    # loaded backend manifests
    lock:      record          # lock record from read-lock
]: nothing -> nothing {

    let lock_providers = ($lock | get --optional providers | default {})
    let lock_backends = ($lock | get --optional backends | default {})

    # Check providers
    for m in $manifests {
        let locked = ($lock_providers | get --optional $m.name | default {})
        let locked_version = ($locked | get --optional version | default "")
        if ($locked_version | is-not-empty) and $locked_version != $m.version {
            error make {
                msg: $"[lock] provider '($m.name)' version mismatch — lock: ($locked_version), manifest: ($m.version) — run: envctl providers list"
            }
        }
    }

    # Check backends
    for b in $backends {
        let locked = ($lock_backends | get --optional $b.name | default {})
        let locked_version = ($locked | get --optional version | default "")
        if ($locked_version | is-not-empty) and $locked_version != $b.version {
            error make {
                msg: $"[lock] backend '($b.name)' version mismatch — lock: ($locked_version), manifest: ($b.version) — run: envctl providers list"
            }
        }
    }

    log detail --ns lock "check passed"
}

# Return lock status as a table — for envctl providers list.
@example "Lock status from empty lock" { lock-status {} }
export def lock-status [lock: record] {
    let providers = ($lock | get --optional providers | default {})
    let backends = ($lock | get --optional backends | default {})
    let provider_rows = ($providers | items {
        |name, spec| {
            kind: provider
            name: $name
            version: ($spec | get --optional version | default "?")
        }
    })

    let backend_rows = ($backends | items {
        |name, spec| {
            kind: backend
            name: $name
            version: ($spec | get --optional version | default "?")
        }
    })

    $provider_rows | append $backend_rows
}
