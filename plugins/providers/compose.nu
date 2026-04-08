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
    let cfg        = (compose-cfg $ctx)
    let services   = ($cfg | get --optional services | default {})
    let selected   = (resolve-selected-services $ctx $cfg)
    let variants   = (resolve-variant-overrides $ctx)
    let base_dir   = (resolve-base-dir $cfg $ctx)
    let base_files = ($cfg | get --optional base_files | default ["compose.yml"])
    let sep        = (path-separator $ctx)

    let from_cli = ($ctx | get --optional cli.ENVCTL_SERVICES | default "")
    if ($from_cli | is-not-empty) {
        compose-log $ctx $"services: ($selected | str join ', ') \(ENVCTL_SERVICES override\)"
    } else if ($selected | is-empty) {
        compose-log $ctx "services: none selected \(no default = true\)"
    } else {
        compose-log $ctx $"services: ($selected | str join ', ') \(default = true\)"
    }

    if ($variants | columns | is-not-empty) {
        let variant_str = ($variants | transpose k v | each {|e| $"($e.k)=($e.v)"} | str join ", ")
        compose-log $ctx $"variants: ($variant_str) \(ENVCTL_VARIANTS override\)"
    }

    compose-log $ctx $"base_dir: ($base_dir)"
    compose-log $ctx $"stage:    ($ctx.stage)"

    (build-file-list $selected $variants $services $base_dir $base_files $ctx.stage $sep $ctx)
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
    if ($raw | is-empty) { return ($env.PWD | to-forward-slashes) }
    # GIT_ROOT_DIR already resolved in env_vars by the time provider runs
    let git_root = ($ctx | get --optional env_vars.GIT_ROOT_DIR | default $env.PWD)
    $raw | str replace --all "{{ GIT_ROOT_DIR }}" $git_root | to-forward-slashes
}

# Normalize path separators to forward slashes.
# path join on Windows produces backslashes; Docker and WSL both accept forward slashes.
def to-forward-slashes []: string -> string {
    str replace --all '\' '/'
}

# Inline logger — cannot import src/core/log.nu from a plugin.
# Mirrors the [detail] format used by the rest of envctl.
# Respects cli.quiet so --quiet suppresses compose detail lines.
def compose-log [ctx: record, msg: string] {
    let quiet = ($ctx | get --optional cli.quiet | default false)
    if not $quiet {
        print $"(ansi dark_gray)[detail]     [compose]     ($msg)(ansi reset)"
    }
}

def log-included [ctx: record, path: string, reason: string] {
    compose-log $ctx $"  + ($path) \(($reason)\)"
}

def log-skipped [ctx: record, path: string, reason: string] {
    compose-log $ctx $"  - ($path) \(($reason)\)"
}

def normalize-variant-list [val: any]: nothing -> list<string> {
    if ($val | describe | str starts-with "list") {
        $val | each {|v| $v | str trim} | where {|v| ($v | is-not-empty)}
    } else {
        $val | into string | split row "," | each {|v| $v | str trim} | where {|v| ($v | is-not-empty)}
    }
}

def build-file-list [
    selected:   list<string>
    variants:   record
    services:   record
    base_dir:   string
    base_files: list<string>
    stage:      string
    sep:        string
    ctx:        record
]: nothing -> string {
    mut files = []

    for f in $base_files {
        let p = ($base_dir | path join $f | to-forward-slashes)
        if ($p | path exists) {
            $files = ($files | append $p)
            log-included $ctx $p "base file"
        } else {
            log-skipped $ctx $p "base file not found"
        }
    }

    let stage_file = ($base_dir | path join $"compose.($stage).yml" | to-forward-slashes)
    if ($stage_file | path exists) {
        $files = ($files | append $stage_file)
        log-included $ctx $stage_file $"root stage file: ($stage)"
    }

    for name in $selected {
        let svc_cfg = ($services | get --optional $name | default {})
        let svc_dir = ($base_dir | path join $name | to-forward-slashes)

        for dep in ($svc_cfg | columns | where $it != "default") {
            let override     = ($variants | get --optional $"($name).($dep)" | default "")
            let raw_val      = if ($override | is-not-empty) {
                $override
            } else {
                $svc_cfg | get --optional $dep | default ""
            }
            let dep_variants = (normalize-variant-list $raw_val)

            for variant in $dep_variants {
                let reason = if ($override | is-not-empty) {
                    $"($name).($dep)=($variant) via ENVCTL_VARIANTS"
                } else {
                    $"($name).($dep)=($variant) default"
                }

                let vf = ($svc_dir | path join $"compose.($name).($dep).($variant).yml" | to-forward-slashes)
                if ($vf | path exists) {
                    $files = ($files | append $vf)
                    log-included $ctx $vf $reason
                } else {
                    log-skipped $ctx $vf $reason
                }

                let vf_stage = ($svc_dir | path join $"compose.($name).($dep).($variant).($stage).yml" | to-forward-slashes)
                if ($vf_stage | path exists) {
                    $files = ($files | append $vf_stage)
                    log-included $ctx $vf_stage $"($reason) / stage: ($stage)"
                }
            }
        }

        let sf = ($svc_dir | path join $"compose.($name).yml" | to-forward-slashes)
        if ($sf | path exists) {
            $files = ($files | append $sf)
            log-included $ctx $sf $"service base: ($name)"
        } else {
            log-skipped $ctx $sf $"service base not found: ($name)"
        }

        let stage_svc_file = ($svc_dir | path join $"compose.($name).($stage).yml" | to-forward-slashes)
        if ($stage_svc_file | path exists) {
            $files = ($files | append $stage_svc_file)
            log-included $ctx $stage_svc_file $"service stage: ($name) / ($stage)"
        }
    }

    let result = ($files | str join $sep)
    if ($files | is-empty) {
        compose-log $ctx "result: (no files found)"
    } else {
        compose-log $ctx $"result: ($files | length) file\(s\)"
    }

    $result
}
