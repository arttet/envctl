# ==============================================================================
# engine/validator.nu — AST validation engine.
#
# Validates an AST subtree (from ast/envfile, ast/secrets, ast/certs projection):
#   1. Provider config schemas   — validates [providers.NAME] against config_schema
#   2. Token linking             — checks {{ provider:NAME.FN }} references exist
#                                  in manifest.provides of the named provider
#   3. Cert declarations         — validates [certs.NAME] structure and constraints
#
# Cert validation rules:
#   external = true  → targets must have exactly one entry
#                    → options.BACKEND.cert and options.BACKEND.key required
#   external = false → config_template required
#                    → options.BACKEND.cert and options.BACKEND.key required per target
#   signed_by        → must reference a known cert name in [certs.*]
#
# Pure — no side effects. Hard error on any violation.
# ==============================================================================

use ../language/grammar.nu [parse-tokens]
use ../schema/validate.nu [validate-schema]

use ../core/log.nu

# Validate an AST subtree against loaded provider manifests.
# Returns the same subtree — validates in place, errors thrown on failure.
@example "Validate empty subtree" { validate { generators: [] secrets: [] certs: [] certs_vars: {} providers: {} cfg: {} } {} }
export def validate [sub_ast: record, providers: record] {
    validate-provider-schemas $sub_ast $providers
    validate-token-links $sub_ast $providers
    validate-certs $sub_ast
    $sub_ast
}

def validate-provider-schemas [sub_ast: record, providers: record] {
    let prov_cfg = ($sub_ast | get --optional cfg.providers | default {})
    for name in ($providers | columns) {
        let m = ($providers | get --optional $name)
        let schema_name = ($m | get --optional config_schema | default "")

        if ($schema_name | is-empty) {
            continue
        }

        let pcfg = ($prov_cfg | get --optional $name | default {})
        log detail --ns validator $"validating provider '($name)' config schema"

        validate-schema $pcfg $schema_name
    }
}

def validate-token-links [sub_ast: record, providers: record] {
    let generators = ($sub_ast | get --optional generators | default [])
    let secrets = ($sub_ast | get --optional secrets | default [])

    for generator in $generators {
        validate-node-tokens $"[generators.($generator.key)]" $generator.tokens $providers
    }

    for secret in $secrets {
        validate-node-tokens $"[secrets.($secret.key)]" $secret.src_tokens $providers
    }
}

def validate-node-tokens [label: string, tokens: list<record>, providers: record] {
    for token in ($tokens | where type == provider) {
        let manifest = ($providers | get --optional $token.name)
        if $manifest == null {
            error make {
                msg: $"($label) provider '($token.name)' not in enabled providers"
            }
        }

        let provides = ($manifest | get --optional provides | default [])
        if not ($token.fn in $provides) {
            error make {
                msg: $"($label) fn '($token.fn)' not in manifest.provides of '($token.name)' — available: ($provides | str join ', ')"
            }
        }
    }
}

def validate-certs [sub_ast: record] {
    let certs = ($sub_ast | get --optional certs | default [])
    if ($certs | is-empty) {
        return
    }

    # Validate signed_by references first — every signed_by must point to known cert
    let cert_names = ($certs | get name)
    for cert in $certs {
        let signed_by = ($cert | get --optional signed_by | default "")
        if ($signed_by | is-not-empty) and not ($signed_by in $cert_names) {
            error make {
                msg: $"[validator] cert '($cert.name)': signed_by = '($signed_by)' not found in [certs.*] — declared: ($cert_names | str join ', ')"
            }
        }
    }

    # Validate each cert declaration
    for cert in $certs {
        let name = $cert.name
        let external = ($cert | get --optional external | default false)
        let targets = ($cert | get --optional targets | default [])
        if ($targets | is-empty) {
            error make {
                msg: $"[validator] cert '($name)': targets is required"
            }
        }

        if $external {
            validate-external-cert $name $targets $cert
        } else {
            validate-generated-cert $name $targets $cert
        }
    }
}

# Validate external cert — read from backend, never generated.
def validate-external-cert [name: string, targets: list<string>, cert: record] {
    # external = true → exactly one target — ambiguous which backend to read from
    if ($targets | length) != 1 {
        error make {
            msg: $"[validator] cert '($name)': external = true requires exactly one target, got ($targets | length) — ($targets | str join ', ')"
        }
    }

    let backend = ($targets | get --optional 0)
    let options = (
        $cert | get --optional options | default {} | get --optional $backend | default {}
    )

    let cert_path = ($options | get --optional cert | default "")
    let key_path = ($options | get --optional key | default "")

    if ($cert_path | is-empty) {
        error make {
            msg: $"[validator] cert '($name)': external = true requires options.($backend).cert"
        }
    }

    if ($key_path | is-empty) {
        error make {
            msg: $"[validator] cert '($name)': external = true requires options.($backend).key"
        }
    }

    log detail --ns validator $"cert '($name)': external — will read from ($backend)"
}

# Validate generated cert — will be created by certs provider.
def validate-generated-cert [name: string, targets: list<string>, cert: record] {
    let config_template = ($cert | get --optional config_template | default "")

    # config_template required for all generated certs
    if ($config_template | is-empty) {
        error make {
            msg: $"[validator] cert '($name)': config_template is required"
        }
    }

    # Each target must have cert and key paths
    for backend in $targets {
        let options = (
            $cert | get --optional options | default {} | get --optional $backend | default {}
        )

        let cert_path = ($options | get --optional cert | default "")
        let key_path = ($options | get --optional key | default "")
        if ($cert_path | is-empty) {
            error make {
                msg: $"[validator] cert '($name)': options.($backend).cert is required"
            }
        }

        if ($key_path | is-empty) {
            error make {
                msg: $"[validator] cert '($name)': options.($backend).key is required"
            }
        }
    }

    let signed_by = ($cert | get --optional signed_by | default "")
    log detail --ns validator $"cert '($name)': generated, signed_by = '($signed_by)'"
}
