# ==============================================================================
# state/state.nu — Local audit state management.
#
# .envctl.state.ndjson — NOT committed to git (add to .gitignore).
# Append-only audit log — one JSON object per line.
# Used for: health checks, drift detection, audit trail.
#
# State entry shape:
#   {
#       action:      string   # "envfile generate" | "secrets generate" | "secrets rotate" | …
#       at:          string   # ISO 8601 timestamp
#       by:          string   # $env.USER or git config user.name
#       stage:       string   # "dev" | "prod" | …
#       profile:     string   # "envfile" | "secrets" | "all"
#       dry_run:     bool
#   }
#
# Format: NDJSON — each line is a valid JSON object.
# Append: one line per event — no full file rewrite needed.
# ==============================================================================

use ../core/constants.nu [DEFAULT_STATE_PATH]
use ../core/log.nu

# Append a new audit entry to .envctl.state.ndjson.
# Creates the file if it does not exist.
@example "Append envfile generate entry" { append-entry "envfile generate" dev envfile false ".envctl.state.ndjson" }
@example "Append secrets rotate entry" { append-entry "secrets rotate" prod secrets false ".envctl.state.ndjson" }
export def append-entry [
    action:  string                      # action label
    stage:   string                      # active stage
    profile: string                      # pipeline profile
    dry_run: bool                        # was this a dry-run?
    path:    string = $DEFAULT_STATE_PATH
]: nothing -> nothing {

    let by = (resolve-actor)
    let entry = {
        action: $action
        at: (date now | format date %Y-%m-%dT%H:%M:%SZ)
        by: $by
        stage: $stage
        profile: $profile
        dry_run: $dry_run
    }

    let line = ($entry | to json --raw)

    # Ensure parent directory exists (.envctl/ may not exist yet)
    mkdir ($path | path dirname)

    # Append — no full rewrite
    $"($line)\n" | save --append $path

    log detail --ns state $"audit entry written: ($action)"
}

# Read all audit entries from .envctl.state.ndjson.
# Returns empty list if file does not exist.
@example "Read state from default path" { read-state ".envctl.state.ndjson" }
@example "Read missing state — returns empty" { read-state ".envctl.missing.ndjson" }
export def read-state [path?: string] {
    let p = ($path | default $DEFAULT_STATE_PATH)

    if not ($p | path exists) {
        return []
    }

    open --raw $p | lines | where ($it | str trim | is-not-empty) | each {|line| $line | from json }
}

# Return the most recent entry for a given action prefix.
@example "Last envfile generate entry" { last-entry "envfile generate" .envctl.state.ndjson }
@example "Last secrets entry" { last-entry secrets .envctl.state.ndjson }
export def last-entry [action_prefix: string, path?: string] {
    read-state $path | where $it.action | str starts-with $action_prefix | last 1 | get --optional 0? | default {}
}

# Return all entries for a given profile.
@example "Entries for envfile profile" { entries-for-profile envfile .envctl.state.ndjson }
export def entries-for-profile [profile: string, path?: string] {
    read-state $path | where profile == $profile
}

# Return audit summary table — last action per profile.
@example "Audit summary" { audit-summary .envctl.state.ndjson }
export def audit-summary [path?: string] {
    let entries = (read-state ($path | default $DEFAULT_STATE_PATH))
    if ($entries | is-empty) {
        return []
    }

    [envfile, secrets, all] | each { |profile|
        let last = (
            $entries
            | where profile == $profile
            | last 1
            | get --optional 0?
        )

        if $last == null {
            return null
        }

        {
            profile:  $profile
            action:   ($last | get --optional action  | default "")
            at:       ($last | get --optional at      | default "")
            by:       ($last | get --optional by      | default "")
            stage:    ($last | get --optional stage   | default "")
            dry_run:  ($last | get --optional dry_run | default false)
        }
    } | where $it != null
}

# Resolve the actor name — $env.USER or git config user.name fallback.
def resolve-actor [] {
    let user = ($env | get --optional USER | default "")
    if ($user | is-not-empty) { return $user }
    try {
        ^git config user.name | str trim
    } catch {
        "unknown"
    }
}
