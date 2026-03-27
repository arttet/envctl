# ==============================================================================
# plugins/providers/password.nu — Password generator provider.
#
# Provides: {{ provider:password.generate-password }}
#
# manifest [] replaces legacy provider [].
# ==============================================================================

export def manifest []: nothing -> record {
    {
        name:          password
        version:       1.0.0
        kind:          provider
        description:   "Generates cryptographically random passwords"
        provides:      [generate-password]
        requires:      []
        config_schema: password.config.schema.toml
        health_schema: password.health.schema.toml
        resolve: {
            generate-password: {|ctx| generate-password $ctx }
        }
        env_vars: [
            {
                name: ENVCTL_PASSWORD_LENGTH
                description: "Override length"
                example: "64"
            }
            {
                name: ENVCTL_PASSWORD_CHARSET
                description: "Override charset"
                example: hex
            }
        ]
    }
}

export def generate-password [ctx: record]: nothing -> string {
    let pcfg = ($ctx | get --optional cfg.providers.password | default {})

    let length = (
        $ctx | get --optional cli.ENVCTL_PASSWORD_LENGTH
        | default ($pcfg | get --optional length | default 32)
        | into int
    )

    let charset = (
        $ctx | get --optional cli.ENVCTL_PASSWORD_CHARSET
        | default ($pcfg | get --optional charset | default alphanumeric)
    )

    let tool = ($pcfg | get --optional tool | default internal)
    if $tool != internal {
        return (call-external-tool $tool $length)
    }

    match $charset {
        "hex"     => { openssl rand -hex $length | str trim }
        "base64"  => { openssl rand -base64 $length | str trim }
        "symbols" => {
            (openssl rand -base64 ($length * 2) | str trim)
            | str replace --all --regex '[^a-zA-Z0-9!@#$%^&*]' ''
            | str substring 0..<$length
        }
        _ => {
            # alphanumeric default
            (openssl rand -base64 ($length * 2) | str trim)
            | str replace --all --regex '[^a-zA-Z0-9]' ''
            | str substring 0..<$length
        }
    }
}

def call-external-tool [tool: string, length: int]: nothing -> string {
    match $tool {
        "openssl" => { openssl rand -base64 $length | str trim }
        "pwgen"   => { pwgen --secure $length 1     | str trim }
        _         => { ^$tool $length                | str trim }
    }
}
