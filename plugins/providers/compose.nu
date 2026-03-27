# ==============================================================================
# plugins/providers/compose.nu — Docker Compose file list provider.
#
# Provides: {{ provider:compose.collect-files }}
#           {{ provider:compose.path-separator }}
#
# manifest [] replaces legacy provider [].
# ==============================================================================


export def manifest []: nothing -> record {
    {
        name:          "compose"
        version:       "1.0.0"
        kind:          "provider"
        description:   "Builds COMPOSE_FILE and COMPOSE_PATH_SEPARATOR for Docker Compose"
        provides:      [collect-files path-separator]
        requires:      [GIT_ROOT_DIR]
        config_schema: "compose.config.schema.toml"
        health_schema: "compose.health.schema.toml"
        resolve: {
            "collect-files":   {|ctx| collect-files $ctx }
            "path-separator":  {|ctx| path-separator $ctx }
        }
        env_vars: [
            {
                name: "ENVCTL_SERVICES"
                description: "Override selected services"
                example: "api,mysql"
            }
            {
                name: "ENVCTL_VARIANTS"
                description: "Override service variants"
                example: "mysql.db=postgres"
            }
        ]
    }
}


export def collect-files [ctx: record]: nothing -> string {
    let cfg      = (compose-cfg $ctx)

    let services = ($cfg | get --optional services | default {})
    let selected = (resolve-selected-services $ctx $cfg)
    let variants = (resolve-variant-overrides $ctx)

    let base_dir = (resolve-base-dir $cfg $ctx)
    let base_files = ($cfg | get --optional base_files | default ["compose.yml"])
    let sep = (path-separator $ctx)

    (build-file-list $selected $variants $services $base_dir $base_files $ctx.stage $sep)
}

export def path-separator [_ctx: record]: nothing -> string {
    if $nu.os-info.name == "windows" { ";" } else { ":" }
}

# Return service names with default = true.
export def default-services [ctx: record]: nothing -> list<string> {
    let cfg = (compose-cfg $ctx)
    $cfg
    | get --optional services
    | default {}
    | transpose name spec
    | where ($it.spec | get --optional default | default false)
    | get name
}

def compose-cfg [ctx: record]: nothing -> record {
    $ctx | get --optional cfg.providers.compose | default {
        base_dir:   ""
        base_files: ["compose.yml"]
        services:   {}
    }
}

def resolve-selected-services [ctx: record, cfg: record]: nothing -> list<string> {
    let from_cli = ($ctx | get --optional cli.ENVCTL_SERVICES | default "")
    if ($from_cli | is-not-empty) {
        return ($from_cli | split row "," | each {|s| $s | str trim })
    }
    # Default: services with default = true
    $cfg
    | get --optional services
    | default {}
    | transpose name spec
    | where ($it.spec | get --optional default | default false)
    | get name
}

def resolve-variant-overrides [ctx: record]: nothing -> record {
    let from_cli = ($ctx | get --optional cli.ENVCTL_VARIANTS | default "")
    if ($from_cli | is-empty) { return {} }

    # Format: "mysql.db=postgres,redis.mode=cluster"
    $from_cli
    | split row ","
    | each {|pair|
        let parts = ($pair | str trim | split row "=")
        let key   = ($parts | first | str trim)
        let val   = ($parts | skip 1 | str join "=" | str trim)
        {key: $key, val: $val}
    }
    | reduce --fold {} {|e, acc| $acc | insert $e.key $e.val }
}

def resolve-base-dir [cfg: record, ctx: record]: nothing -> string {
    let raw = ($cfg | get --optional base_dir | default "")
    if ($raw | is-empty) { return $env.PWD }
    # GIT_ROOT_DIR already resolved in env_vars by the time provider runs
    let git_root = ($ctx | get --optional env_vars.GIT_ROOT_DIR | default $env.PWD)
    $raw | str replace --all "{{ GIT_ROOT_DIR }}" $git_root
}

def build-file-list [
    selected:   list<string>
    variants:   record
    services:   record
    base_dir:   string
    base_files: list<string>
    stage:      string
    sep:        string
]: nothing -> string {
    mut files = []

    for f in $base_files {
        let p = ($base_dir | path join $f)
        if ($p | path exists) { $files = ($files | append $p) }
    }

    let stage_file = ($base_dir | path join $"compose.($stage).yml")
    if ($stage_file | path exists) {
        $files = ($files | append $stage_file)
    }

    for name in $selected {
        let svc_cfg = ($services | get --optional $name | default {})
        let svc_dir = ($base_dir | path join $name)

        for dep in ($svc_cfg | columns | where $it != "default") {
            let variant = (
                $variants | get --optional $"($name).($dep)"
                | default ($svc_cfg | get --optional $dep | default "")
            )

            let vf = ($svc_dir | path join $"compose.($name).($dep).($variant).yml")
            if ($vf | path exists) {
                $files = ($files | append $vf)
            }
        }

        let sf = ($svc_dir | path join $"compose.($name).yml")
        if ($sf | path exists) {
            $files = ($files | append $sf)
        }
    }

    $files | str join $sep
}
