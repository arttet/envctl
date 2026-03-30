# ==============================================================================
# engine/plan.nu — ExecutionPlan builder.
#
# Converts validated AST subtree into a flat list of typed actions.
# Multi-pass generator resolution with cycle detection.
#
# Action kinds:
#   write-env    — render and write .env file
#   write-secret — generate secret value via provider, write via backend
#   write-cert   — generate cert+key in memory via certs provider, write via backend
#   read-cert    — read existing cert+key from backend (external = true)
#
# Pure — no side effects.
# ==============================================================================

use ./queries.nu

use ../language/grammar.nu [resolve]
use ../core/constants.nu [MAX_GENERATOR_PASSES]

@example "Build plan for envfile profile" { build {env_vars: {}, dry_run: false, cfg: {}, cli: {}} { generators: [] secrets: [] certs: [] certs_vars: {} envfile: {file: ".env", pattern: ".env.example", excluded: []} providers: {} cfg: {} } "envfile" {} }
export def build [
    ctx: record
    sub_ast: record
    profile: string
    providers: record
] {
    let resolved_generators = (resolve-generators $sub_ast $providers $ctx)
    let actions = match $profile {
        "envfile" => (build-envfile-actions $sub_ast $resolved_generators)
        "secrets" => (build-secrets-actions $sub_ast $resolved_generators $ctx)
        "certs" => (build-cert-actions $sub_ast $resolved_generators $ctx)
        "all" => ((build-cert-actions $sub_ast $resolved_generators $ctx) | append (build-secrets-actions $sub_ast $resolved_generators $ctx) | append (build-envfile-actions $sub_ast $resolved_generators))
        _ => {
            error make {
                msg: $"[plan] unknown profile: ($profile)"
            }
        }
    }

    {
        profile: $profile
        dry_run: $ctx.dry_run
        generators: $resolved_generators
        actions: $actions
    }
}

# Set all write actions to overwrite mode with backup enabled.
export def set-rotate-mode [] {
    let plan = $in
    let updated_actions = ($plan.actions | each {|a|
        if ($a.kind == "write-secret") or ($a.kind == "write-cert") {
                $a | upsert mode "overwrite" | upsert backup true
            } else {
                $a
            }
        }
    )

    $plan | upsert actions $updated_actions
}

# Set a specific write action to overwrite mode with backup enabled.
export def set-rotate-one [plan: record, key: string] {
    let updated_actions = ($plan.actions | each {|a|
        let match_key = ($a | get --optional key  | default "")
        let match_name = ($a | get --optional name | default "")

        if (($a.kind == "write-secret") or ($a.kind == "write-cert")) and (
            $match_key == $key or $match_name == $key
        ) {
            $a | upsert mode "overwrite" | upsert backup true
        } else {
            $a
        }
    })

    $plan | upsert actions $updated_actions
}

def resolve-generators [sub_ast: record, providers: record, ctx: record] {
    let nodes = (queries generators $sub_ast)
    if ($nodes | is-empty) {
        return {}
    }

    mut resolved = {}
    mut remaining = $nodes
    mut passes = 0

    loop {
        if ($remaining | is-empty) {
            break
        }

        if $passes >= $MAX_GENERATOR_PASSES {
            let stuck = ($remaining | get key | str join ", ")
            error make {
                msg: $"[plan] generator cycle or unresolvable after ($MAX_GENERATOR_PASSES) passes: ($stuck)"
            }
        }

        mut next_remaining = []
        for node in $remaining {
            let resolve_ctx = {
                env_vars: $resolved
                secrets_root: (queries secrets-root $sub_ast)
                providers: $providers
                cfg: ($sub_ast | get --optional cfg | default {})
                cli: ($ctx | get --optional cli | default {})
            }

            let value = (try {
                resolve $node.raw $resolve_ctx
            } catch {
                null
            })

            if $value != null and not ($value | str contains "{{") {
                $resolved = ($resolved | insert $node.key $value)
            } else {
                $next_remaining = ($next_remaining | append $node)
            }
        }

        $remaining = $next_remaining
        $passes += 1
    }

    $resolved
}

def build-envfile-actions [sub_ast: record, resolved_generators: record] {
    let envfile = ($sub_ast | get --optional envfile | default {})
    let file = ($envfile | get --optional file | default ".env")
    let pattern = ($envfile | get --optional pattern | default ".env.example")

    if ($pattern | is-empty) {
        return []
    }

    [
        {
            kind: "write-env"
            file: $file
            pattern: $pattern
            generators: $resolved_generators
            excluded: ($envfile | get --optional excluded | default [])
        }
    ]
}

def build-secrets-actions [sub_ast: record, resolved_generators: record, ctx: record] {
    let secret_nodes = (queries secrets $sub_ast)
    if ($secret_nodes | is-empty) { return [] }
    let secrets_root = (queries secrets-root $sub_ast)
    let actions = ($secret_nodes | each {|s|
        let targets = ($s | get --optional targets | default ["file"])

        $targets | each {|target|
            let raw_opts      = ($s | get --optional options | default {})
            let opts          = ($raw_opts | get --optional $target | default {})
            let raw_path      = ($opts | get --optional path | default "")
            let resolved_path = (resolve-option-token $raw_path $resolved_generators $ctx $secrets_root)

            {
                kind:             "write-secret"
                key:              $s.key
                value_source:     $s.value_source
                src_tokens:       $s.src_tokens
                mode:             "create-only"
                backup:           false
                backend:          $target
                options:          ($opts | upsert path $resolved_path)
                secrets_root:     $secrets_root
                provider_options: ($s | get --optional provider_options | default {})
            }
        }
    } | flatten)

    topo-sort-secrets $actions
}

# Sort write-secret actions so {{ secret:IDENT }} dependencies execute first.
# Uses iterative stabilization — safe for DAGs, appends any cycle remainder unchanged.
def topo-sort-secrets [actions: list<record>] {
    let all_keys = ($actions | get key)
    mut remaining = $actions
    mut sorted = []
    mut passes = 0
    let max_passes = (($actions | length) + 1)

    while (not ($remaining | is-empty)) and ($passes < $max_passes) {
        let resolved_keys = (if ($sorted | is-empty) { [] } else { $sorted | get key })
        mut next_remaining = []

        for action in $remaining {
            let src_tokens = ($action | get --optional src_tokens | default [])
            let secret_deps = (
                $src_tokens
                | where type == secret
                | get ident
                | where {|k| $k in $all_keys}
            )
            let unmet = ($secret_deps | where {|d| $d not-in $resolved_keys})

            if ($unmet | is-empty) {
                $sorted = ($sorted | append $action)
            } else {
                $next_remaining = ($next_remaining | append $action)
            }
        }

        $remaining = $next_remaining
        $passes += 1
    }

    $sorted | append $remaining
}

def build-cert-actions [sub_ast: record, resolved_generators: record, ctx: record] {

    let cert_nodes = (queries certs $sub_ast)
    if ($cert_nodes | is-empty) {
        return []
    }

    let certs_vars = ($sub_ast | get --optional certs_vars | default {})
    let generators_merged = ($resolved_generators | merge $certs_vars)
    let secrets_root = (queries secrets-root $sub_ast)

    $cert_nodes | each {|c|
        let external = ($c | get --optional external | default false)
        let targets  = ($c | get --optional targets  | default ["file"])

        $targets | each {|target|
            let raw_opts = ($c | get --optional options | default {})
            let opts     = ($raw_opts | get --optional $target | default {})

            let raw_cert      = ($opts | get --optional cert | default "")
            let raw_key       = ($opts | get --optional key  | default "")
            let resolved_cert = (resolve-option-token $raw_cert $generators_merged $ctx $secrets_root)
            let resolved_key  = (resolve-option-token $raw_key  $generators_merged $ctx $secrets_root)
            let resolved_opts = ($opts | upsert cert $resolved_cert | upsert key $resolved_key)

            if $external {
                {
                    kind:    "read-cert"
                    name:    $c.name
                    backend: $target
                    options: $resolved_opts
                }
            } else {
                let raw_tmpl      = ($c | get --optional config_template | default "")
                let resolved_tmpl = (resolve-option-token $raw_tmpl $generators_merged $ctx $secrets_root)

                {
                    kind:            "write-cert"
                    name:            $c.name
                    signed_by:       ($c | get --optional signed_by | default "")
                    config_template: $resolved_tmpl
                    days:            ($c | get --optional days | default 365)
                    mode:            "create-only"
                    backup:          false
                    backend:         $target
                    options:         $resolved_opts
                    certs_vars:      $generators_merged
                    cfg:             $c.cfg
                }
            }
        }
    } | flatten
}

def resolve-option-token [
    raw: string
    resolved_generators: record
    ctx: record
    secrets_root: string
] {
    if ($raw | is-empty) or not ($raw | str contains "{{") {
        return $raw
    }

    let env_merged = (
        $ctx | get --optional env_vars | default {} | merge $resolved_generators
    )

    let resolve_ctx = {
        env_vars: $env_merged
        secrets_root: $secrets_root
        providers: {}
        cfg: ($ctx | get --optional cfg | default {})
        cli: ($ctx | get --optional cli | default {})
    }

    (try {
        resolve $raw $resolve_ctx
    } catch {
        $raw
    })
}
