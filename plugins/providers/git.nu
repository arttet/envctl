# ==============================================================================
# plugins/providers/git.nu — Git workspace provider.
#
# Provides: {{ provider:git.top-level-dir }}
#
# manifest [] replaces legacy provider [].
# ==============================================================================

export def manifest []: nothing -> record {
    {
        name:          git
        version:       1.0.0
        kind:          provider
        description:   "Resolves GIT_ROOT_DIR from git repository root"
        provides:      [top-level-dir]
        requires:      []
        config_schema: git.config.schema.toml
        health_schema: git.health.schema.toml
        resolve: {
            top-level-dir: {|ctx| top-level-dir $ctx }
        }
        env_vars: [
            {
                name:        ENVCTL_GIT_ROOT
                description: "Override GIT_ROOT_DIR — skips git rev-parse"
                example:     /home/user/myproject
            }
        ]
    }
}

export def top-level-dir [ctx: record]: nothing -> string {
    let override = ($ctx | get --optional cli.ENVCTL_GIT_ROOT | default "")
    if ($override | is-not-empty) {
        return $override
    }

    try {
        git rev-parse --show-toplevel | str trim
    } catch {
        log warn "[git] git rev-parse failed — falling back to $env.PWD"
        $env.PWD
    }
}
