# ==============================================================================
# engine/parser.nu — Config loader and AST builder.
#
# Responsibilities:
#   - Open .envctl.toml from disk
#   - Apply schema defaults
#   - Build full AST — enriched record with typed nodes
#
# Absorbs: config/loader.nu, config/defaults.nu
#
# AST node types:
#   generator: { kind, key, raw, tokens, resolved, errors }
#   secret:    { kind, key, value_source, targets, options, errors }
#   cert:      { kind, name, external, signed_by, config_template, days, targets, options, cfg, errors }
#
# Cert section convention:
#   scalar fields → substitution variables (available as {{ UPPER_KEY }} in templates)
#   record fields → cert declarations
#
# Pure — no side effects, no file writes.
# ==============================================================================

use ../core/constants.nu [DEFAULT_ENVFILE, DEFAULT_PATTERN, DEFAULT_SECRETS_DIR, SCHEMAS_DIR]
use ../language/keywords.nu [
    secrets-service-keys
    KEYWORD_PROVIDERS
    KEYWORD_GENERATORS
    KEYWORD_SECRETS
    KEYWORD_ENVFILE
    KEYWORD_CERTS
]
use ../language/grammar.nu [parse-tokens]
use ../schema/validate.nu [validate-schema, apply-defaults]

def config-defaults [] {
    {
        schema: v1

        generators: {}

        providers: {
            enabled: []
        }

        envfile: {
            file: $DEFAULT_ENVFILE
            pattern: $DEFAULT_PATTERN
            excluded: []
        }

        secrets: {
            base_dir: $DEFAULT_SECRETS_DIR
        }

        certs: {}
    }
}

# Open .envctl.toml and merge with hardcoded defaults.
# Returns normalized cfg record — schema defaults applied and validated.
# Missing file is valid — defaults fill everything.
@example "Parse from default path" { parse-config ".envctl.toml" }
@example "Parse from custom path" { parse-config ".envctl.prod.toml" }
@example "Parse missing file — returns defaults" { parse-config ".envctl.missing.toml" }
export def parse-config [path: path] {
    let raw = if ($path | path exists) {
        config-defaults | merge deep (open $path)
    } else {
        config-defaults
    }

    let normalized = (apply-defaults $raw envctl.config.schema.toml)
    validate-schema $normalized envctl.config.schema.toml
    build-ast $normalized
}

# Build full AST from normalized cfg record.
def build-ast [cfg: record] {
    {
        cfg: $cfg
        generators: (build-generator-nodes $cfg)
        secrets: (build-secret-nodes $cfg)
        certs: (build-cert-nodes $cfg)
        certs_vars: (build-certs-vars $cfg)
        envfile: (build-envfile-node $cfg)
        providers: (build-provider-nodes $cfg)
    }
}

def build-generator-nodes [cfg: record] {
    let gens = ($cfg | get --optional generators | default {})
    if ($gens | is-empty) {
        return []
    }

    $gens | columns | each {|key|
        let raw    = ($gens | get --optional $key | into string)
        let tokens = (parse-tokens $raw)
        {
            kind:     generator
            key:      $key
            raw:      $raw
            tokens:   $tokens
            resolved: null
            errors:   []
        }
    }
}

# Build secret AST nodes from [secrets.NAME] sections.
# Filters out service keys (base_dir, excluded).
# provider_options captures per-secret overrides (length, charset, tool) that shadow
# the global [providers.NAME] config when the secret is resolved.
@example "Build secret nodes from empty cfg" { build-secret-nodes { secrets: { base_dir: "." } } }
@example "Build secret nodes with provider overrides" { build-secret-nodes { secrets: { base_dir: ".", MY_SECRET: { value_source: "{{ provider:password.generate-password }}", targets: ["file"], length: 64, charset: "hex" } } } }
export def build-secret-nodes [cfg: record] {
    let secrets_cfg = ($cfg | get --optional secrets | default {})
    let svc_keys = (secrets-service-keys)
    let keys = ($secrets_cfg | columns | where $it not-in $svc_keys)
    if ($keys | is-empty) { return [] }
    $keys | each {|key|
        let spec       = ($secrets_cfg | get --optional $key)
        let value_src  = ($spec | get --optional value_source | default "" | into string)
        let src_tokens = (parse-tokens $value_src)

        let pw_length  = ($spec | get --optional length)
        let pw_charset = ($spec | get --optional charset)
        let pw_tool    = ($spec | get --optional tool)
        mut provider_options = {}
        if $pw_length  != null { $provider_options = ($provider_options | insert length  $pw_length) }
        if $pw_charset != null { $provider_options = ($provider_options | insert charset $pw_charset) }
        if $pw_tool    != null { $provider_options = ($provider_options | insert tool    $pw_tool) }

        {
            kind:             secret
            key:              $key
            value_source:     $value_src
            src_tokens:       $src_tokens
            targets:          ($spec | get --optional targets | default [file])
            options:          ($spec | get --optional options | default {})
            provider_options: $provider_options
            errors:           []
        }
    }
}

# Extract substitution variables from scalar fields in [certs].
# Convention: scalar → variable, record → cert declaration.
#
# list<string> fields → joined with "," → single string variable
#
# Example:
#   [certs]
#   tool         = "openssl"       → TOOL         = "openssl"
#   key_bits     = 4096            → KEY_BITS      = "4096"
#   organization = "My Project"    → ORGANIZATION  = "My Project"
#   dns_names    = ["a", "b"]      → DNS_NAMES     = "a,b"
@example "Build certs vars from empty cfg" { build-certs-vars {certs: {}} }
@example "Build certs vars from cfg" { build-certs-vars {certs: {tool: openssl, key_bits: 4096}} }
export def build-certs-vars [cfg: record] {
    let certs_cfg = ($cfg | get --optional certs | default {})
    $certs_cfg | columns | where {|k|
        let v = ($certs_cfg | get --optional $k)
        let t = ($v | describe)
        not ($t | str starts-with "record")
    } | reduce --fold {} {|k, acc|
        let v   = ($certs_cfg | get --optional $k)
        let t   = ($v | describe)
        let str_val = if ($t | str starts-with list) {
            $v | each {|i| $i | into string } | str join ,
        } else {
            $v | into string
        }
        $acc | insert ($k | str upcase) $str_val
    }
}

# Build cert AST nodes from record fields in [certs].
# Topological sort by signed_by — root first, leaves last.
def build-cert-nodes [cfg: record] {
    let certs_cfg = ($cfg | get --optional certs | default {})
    # Only record fields are cert declarations
    let cert_keys = ($certs_cfg | columns | where {|k|
        $certs_cfg | get --optional $k | describe | str starts-with "record"
    })

    if ($cert_keys | is-empty) {
        return []
    }

    let nodes = ($cert_keys | each {|key|
        let cert_cfg = ($certs_cfg | get --optional $key)
        {
            kind:            cert
            name:            $key
            external:        ($cert_cfg | get --optional external        | default false)
            signed_by:       ($cert_cfg | get --optional signed_by       | default "")
            config_template: ($cert_cfg | get --optional config_template | default "")
            days:            ($cert_cfg | get --optional days            | default 365)
            targets:         ($cert_cfg | get --optional targets         | default [file])
            options:         ($cert_cfg | get --optional options         | default {})
            cfg:             $cert_cfg
            errors:          []
        }
    })

    topo-sort-certs ...$nodes
}

# Topological sort — root CA first, then intermediate, then leaves.
# Hard error on cycle or unknown signed_by reference.
def topo-sort-certs [...nodes: record] {
    if ($nodes | is-empty) {
        return []
    }

    mut sorted = []
    mut pending = $nodes
    loop {
        if ($pending | is-empty) {
            break
        }

        let before = ($pending | length)
        let sorted_names = ($sorted | get name)
        mut next_pending = []
        for node in $pending {
            let dep = ($node | get --optional signed_by | default "")
            let ready = ($dep | is-empty) or ($dep in $sorted_names)
            if $ready { $sorted ++= [$node] } else { $next_pending ++= [$node] }
        }

        $pending = $next_pending
        if ($pending | length) == $before {
            let stuck = ($pending | get name | str join ", ")
            error make {
                msg: $"[parser] cert dependency cycle or unknown signed_by: ($stuck)"
            }
        }
    }

    $sorted
}

def build-envfile-node [cfg: record] {
    let ef = ($cfg | get --optional envfile | default {})

    {
        file: ($ef | get --optional file | default $DEFAULT_ENVFILE)
        pattern: ($ef | get --optional pattern | default $DEFAULT_PATTERN)
        excluded: ($ef | get --optional excluded | default [])
    }
}

def build-provider-nodes [cfg: record] {
    let enabled = ($cfg | get --optional providers.enabled | default [])
    let prov_cfg = ($cfg | get --optional providers | default {})

    $enabled | reduce --fold {} {|name, acc|
        let pcfg = ($prov_cfg | get --optional $name | default {})
        $acc | insert $name $pcfg
    }
}
