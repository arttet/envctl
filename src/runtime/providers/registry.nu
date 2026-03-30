# ==============================================================================
# plugins/providers/registry.nu — Provider loading.
#
# ONLY file that imports plugins/providers/*.nu directly.
# Loads provider manifests — manifest [] replaces legacy provider [].
# Custom providers loaded via nu --commands.
# ==============================================================================

use ../../../plugins/providers/git.nu
use ../../../plugins/providers/password.nu
use ../../../plugins/providers/compose.nu
use ../../../plugins/providers/certs.nu
use ../../../plugins/providers/rsa.nu

use ../../language/keywords.nu [KEYWORD_MANIFEST]

use ../../core/log.nu

def builtin-providers [] {
    {
        git: {|| git manifest }
        password: {|| password manifest }
        compose: {|| compose manifest }
        certs: {|| certs manifest }
        rsa: {|| rsa manifest }
    }
}

# Load manifest records for all enabled providers.
@example "Load from empty config" { load-providers { cfg: { providers: { enabled: [] } } } }
@example "Load git and password" { load-providers { cfg: { providers: { enabled: [ git password ] } } } }
export def load-providers [ast: record] {
    let enabled = ($ast | get --optional cfg.providers.enabled | default [])
    let builtins = (builtin-providers)

    $enabled | each {|name|
        if $builtins has $name {
            do ($builtins | get --optional $name)
        } else {
            load-custom-provider $ast $name
        }
    }
}

# List all loaded providers as a summary table.
@example "List providers from empty ast" { list-providers { cfg: { providers: {enabled: [] } } } }
export def list-providers [ast: record] {
    load-providers $ast | each {|m|
        {
            name:        $m.name
            version:     $m.version
            kind:        ($m | get --optional kind        | default provider)
            description: ($m | get --optional description | default "")
            provides:    ($m | get --optional provides    | default [] | str join ", ")
            requires:    ($m | get --optional requires    | default [] | str join ", ")
            env_vars:    ($m | get --optional env_vars    | default [] | each {|e| $e.name } | str join ", ")
        }
    }
}

def load-custom-provider [ast: record, name: string] {
    let prov_cfg = ($ast | get --optional cfg.providers | default {})
    let path = (
        $prov_cfg | get --optional $name | default {} | get --optional path | default ""
    )

    if ($path | is-empty) {
        error make {
            msg: $"[registry] provider '($name)' not a builtin and has no path in [providers.($name)]"
        }
    }

    if not ($path | path exists) {
        error make {
            msg: $"[registry] provider '($name)' file not found: ($path)"
        }
    }

    let result = (nu --commands $"use ($path); ($KEYWORD_MANIFEST) | to nuon" | complete)
    if $result.exit_code != 0 {
        error make {
            msg: $"[registry] provider '($name)' must export 'manifest []'\n($result.stderr)"
        }
    }

    $result.stdout | from nuon
}
