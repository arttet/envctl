# ==============================================================================
# plugins/providers/rsa.nu — RSA private key generator provider.
#
# Provides: {{ provider:rsa.generate-rsa-key }}
#
# Generates RSA private keys in PKCS1 (openssl genrsa) or PKCS8 format.
# PKCS1 is the default — compatible with JWT libraries expecting PEM encoded
# PKCS1 or PKCS8 RSA keys (e.g. golang-jwt/jwt, jsonwebtoken).
#
# manifest [] replaces legacy provider [].
# ==============================================================================

export def manifest []: nothing -> record {
    {
        name:           rsa
        version:        1.0.0
        kind:           provider
        description:    "Generates RSA private keys in PKCS1 or PKCS8 PEM format"
        provides:       [generate-rsa-key]
        requires:       []
        requires_tools: [
            { name: openssl, min_version: "" }
        ]
        config_schema: rsa.config.schema.toml
        health_schema: rsa.health.schema.toml
        resolve: {
            generate-rsa-key: {|ctx| generate-rsa-key $ctx }
        }
        env_vars: []
    }
}

export def generate-rsa-key [ctx: record]: nothing -> string {
    let rcfg = ($ctx | get --optional cfg.providers.rsa | default {})

    let key_bits = (
        $rcfg | get --optional key_bits | default 2048 | into int
    )

    let format = (
        $rcfg | get --optional format | default pkcs1
    )

    let tmp_key = (mktemp --suffix .pem)

    try {
        openssl genrsa -out $tmp_key $key_bits

        let pem = match $format {
            "pkcs8" => {
                let tmp_p8 = (mktemp --suffix .p8.pem)
                try {
                    (openssl pkcs8 -topk8 -nocrypt -in $tmp_key -out $tmp_p8)
                    let result = (open --raw $tmp_p8)
                    rm --force $tmp_p8
                    $result
                } catch {|err|
                    rm --force $tmp_p8
                    error make {msg: $"[rsa] failed to convert to PKCS8: ($err.msg)"}
                }
            }
            _ => { open --raw $tmp_key }
        }

        rm --force $tmp_key
        $pem
    } catch {|err|
        rm --force $tmp_key
        error make {msg: $"[rsa] failed to generate RSA key \(($key_bits)-bit\): ($err.msg)"}
    }
}
