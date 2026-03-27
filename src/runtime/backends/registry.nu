# ==============================================================================
# plugins/backends/registry.nu — Backend loading.
#
# ONLY file that imports plugins/backends/*.nu directly.
# Loads backend manifests — manifest [] replaces legacy provider [].
# Returns full manifest record including write_fn, exists_fn, health_fn closures.
# ==============================================================================

use ../../../plugins/backends/file.nu
use ../../language/keywords.nu [KEYWORD_MANIFEST]

use ../../core/log.nu

def builtin-backends [] {
    {
        file: {|| file manifest }
    }
}

# Load a backend manifest record by name.
# Returns manifest with write_fn, exists_fn, health_fn closures attached.
@example "Load file backend" { load-backend file }
export def load-backend [name: string] {
    let builtins = (builtin-backends)
    if $builtins has $name {
        do ($builtins | get --optional $name)
    } else {
        error make {
            msg: $"[backends] unknown backend '($name)' — available: ($builtins | columns | str join ', ')"
        }
    }
}

# List all registered backend names.
@example "List available backends" { list-backends }
export def list-backends [] {
    builtin-backends | columns
}

# Load all backends referenced in an ExecutionPlan.
# Returns deduplicated list of manifest records.
@example "Load backends from empty plan" { load-plan-backends {actions: []} }
export def load-plan-backends [plan: record] {
    $plan.actions | where kind == write-secret | get backend | uniq | each {|name| load-backend $name }
}
