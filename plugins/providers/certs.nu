# ==============================================================================
# plugins/providers/certs.nu — PKI certificate chain provider.
#
# Generates certificates in memory via openssl + mktemp.
# Returns { cert: string, key: string } — PEM content, never writes to disk.
# Writing is handled by the backend (file, vault, infisical).
#
# Signer cert+key passed via ctx.completed_certs — PEM strings read from
# backend by executor before calling this provider.
#
# Type detection via signed_by:
#   signed_by empty  → self-signed Root CA
#   signed_by set    → signed by named CA (intermediate or leaf)
#
# Config template tokens resolved from (low → high priority):
#   ctx.env_vars (.env)
#       ↑
#   action.certs_vars (scalar fields from [certs])
#       ↑
#   action.cfg scalar fields (from [certs.NAME])
#
# Template convention (signed certs):
#   req_extensions = v3_X_req   — CSR section, NO authorityKeyIdentifier
#   v3_X                        — signing section, WITH authorityKeyIdentifier = keyid,issuer
#   detect-signing-section strips the _req suffix to find the signing section name.
#
# Requires openssl >= 3.0
# ==============================================================================

export def manifest []: nothing -> record {
    {
        name:           certs
        version:        1.0.0
        kind:           provider
        description:    "Generates PKI certificate chains via openssl"
        provides:       [generate-cert]
        requires:       []
        requires_tools: [
            { name: openssl, min_version: 3.0.0 }
        ]
        config_schema: certs.config.schema.toml
        health_schema: certs.health.schema.toml
        resolve: {
            generate-cert: {|ctx| generate-cert $ctx }
        }
        env_vars: []
    }
}

# Generate a certificate pair in memory.
# Reads current_cert_action from ctx — injected by executor.
# Reads signer PEM from ctx.completed_certs — populated by executor.
# Returns { cert: string, key: string } PEM content.
export def generate-cert [ctx: record]: nothing -> record {
    let action    = ($ctx | get --optional current_cert_action)
    if $action == null {
        error make {msg: "[certs] generate-cert called without current_cert_action in ctx"}
    }

    let signed_by = ($action | get --optional signed_by | default "")

    if ($signed_by | is-empty) {
        generate-self-signed $ctx $action
    } else {
        generate-signed $ctx $action $signed_by
    }
}

# Self-signed Root CA — no signer needed.
def generate-self-signed [ctx: record, action: record]: nothing -> record {
    let resolve_ctx = (build-resolve-ctx $ctx $action)
    let cnf_path    = (render-config-template $action $resolve_ctx)
    let days        = ($action | get --optional days | default 3650)

    let tmp_cert = (mktemp --suffix .crt)
    let tmp_key  = (mktemp --suffix .key)

    try {
        let cmd = [
            openssl req -x509
            -newkey $"rsa:($resolve_ctx.key_bits)"
            -sha256
            -keyout $tmp_key
            -out    $tmp_cert
            -days   ($days | into string)
            -nodes
            -config $cnf_path
        ]
        print $"[certs] ($cmd | str join ' ')"
        ^($cmd | first) ...($cmd | skip 1)

        let result = {
            cert: (open --raw $tmp_cert)
            key:  (open --raw $tmp_key)
        }

        rm --force $tmp_cert $tmp_key $cnf_path
        $result
    } catch {|err|
        rm --force $tmp_cert $tmp_key $cnf_path
        error make {
            msg: $"[certs] failed to generate root CA '($action.name)': ($err.msg)"
        }
    }
}

# Signed cert — intermediate CA or leaf.
# CSR extensions embedded via req_extensions = v3_X_req in config_template.
# Signing extensions applied via -extfile -extensions v3_X (strips _req suffix).
# authorityKeyIdentifier must only appear in the signing section, not the CSR section.
# Signer PEM read from ctx.completed_certs — written to mktemp for openssl, then deleted.
def generate-signed [ctx: record, action: record, signed_by: string]: nothing -> record {
    let resolve_ctx   = (build-resolve-ctx $ctx $action)
    let cnf_path      = (render-config-template $action $resolve_ctx)
    let days          = ($action | get --optional days | default 365)
    let signing_sec   = (detect-signing-section $cnf_path $action.name)

    # Get signer PEM from completed_certs
    let completed = ($ctx | get --optional completed_certs | default {})
    let signer    = ($completed | get --optional $signed_by)
    if $signer == null {
        error make {
            msg: $"[certs] signer '($signed_by)' not found in completed_certs — ensure '($signed_by)' was generated first"
        }
    }

    # Write signer PEM to temp files — only for openssl duration
    let tmp_ca_cert = (mktemp --suffix .ca.crt)
    let tmp_ca_key  = (mktemp --suffix .ca.key)
    let tmp_cert    = (mktemp --suffix .crt)
    let tmp_key     = (mktemp --suffix .key)
    let tmp_csr     = (mktemp --suffix .csr)

    $signer.cert | save --force $tmp_ca_cert
    $signer.key | save --force $tmp_ca_key

    try {
        # Generate key + CSR — req_extensions = v3_X_req embeds extensions (without AKI)
        let cmd_req = [
            openssl req
            -newkey $"rsa:($resolve_ctx.key_bits)"
            -sha256
            -keyout $tmp_key
            -out    $tmp_csr
            -nodes
            -config $cnf_path
        ]
        print $"[certs] ($cmd_req | str join ' ')"
        ^($cmd_req | first) ...($cmd_req | skip 1)

        # Sign: apply signing extensions from v3_X section (includes authorityKeyIdentifier)
        let cmd_sign = [
            openssl x509 -req
            -in      $tmp_csr
            -CA      $tmp_ca_cert
            -CAkey   $tmp_ca_key
            -CAcreateserial
            -out     $tmp_cert
            -days    ($days | into string)
            -sha256
            -extfile $cnf_path
            -extensions $signing_sec
        ]
        print $"[certs] ($cmd_sign | str join ' ')"
        ^($cmd_sign | first) ...($cmd_sign | skip 1)

        let result = {
            cert: (open --raw $tmp_cert)
            key:  (open --raw $tmp_key)
        }

        rm --force $tmp_ca_cert $tmp_ca_key $tmp_cert $tmp_key $tmp_csr $cnf_path
        $result
    } catch {|err|
        rm --force $tmp_ca_cert $tmp_ca_key $tmp_cert $tmp_key $tmp_csr $cnf_path
        error make {msg: $"[certs] failed to generate cert '($action.name)': ($err.msg)"}
    }
}

# Read req_extensions from rendered cnf, strip _req suffix → signing section name.
# e.g. req_extensions = v3_intermediate_ca_req  →  v3_intermediate_ca
def detect-signing-section [cnf_path: path, cert_name: string]: nothing -> string {
    let content = (open --raw $cnf_path)
    let match   = ($content | parse --regex 'req_extensions\s*=\s*(\S+)' | get --optional 0?)

    if $match == null {
        error make {
            msg: $"[certs] no req_extensions found in config_template for cert '($cert_name)'"
        }
    }

    let found = ($match | get capture0 | str trim)

    if ($found | str ends-with _req) {
        $found | str substring 0..<(($found | str length) - 4)
    } else {
        error make {
            msg: $"[certs] req_extensions value '($found)' must end with '_req' — signing section is the name without the '_req' suffix, for cert '($cert_name)'"
        }
    }
}

# Render .cnf.tmpl → temp file with {{ }} tokens resolved.
# Returns path to rendered temp file — caller must rm after use.
def render-config-template [action: record, resolve_ctx: record]: nothing -> string {
    let tmpl_path = ($action | get --optional config_template | default "")

    if ($tmpl_path | is-empty) {
        error make {msg: $"[certs] config_template is required for cert '($action.name)'"}
    }

    if not ($tmpl_path | path exists) {
        error make {msg: $"[certs] config_template not found: ($tmpl_path)"}
    }

    let raw = (open --raw $tmpl_path)
    let rendered = (resolve-template-tokens $raw $resolve_ctx $action.name)
    let tmp_cnf  = (mktemp --suffix .cnf)

    $rendered | save --force $tmp_cnf
    $tmp_cnf
}

def resolve-template-tokens [content: string, resolve_ctx: record, cert_name: string]: nothing -> string {
    let pattern = '\{\{\s*([^}]+?)\s*\}\}'
    mut result  = $content

    while ($result | str contains "{{") {
        let match = ($result | parse --regex $pattern | get --optional 0?)
        if $match == null { break }

        let raw_expr = ($match | get capture0 | str trim)
        let key      = ($raw_expr | str upcase | str replace --all --regex \s+ _)
        let value    = ($resolve_ctx.env_vars | get --optional $key | default "")

        if ($value | is-empty) {
            error make {
                msg: $"[certs] unresolved token '{{ ($raw_expr) }}' in config_template for cert '($cert_name)' — set '($key)' in [certs] or [certs.($cert_name)]"
            }
        }

        let escaped    = ($raw_expr | regex-escape)
        let full_match = $"\\{\\{\\s*($escaped)\\s*\\}\\}"
        $result = ($result | str replace --regex $full_match $value)
    }

    $result
}

# Build the token resolution context for config template rendering.
# Merges (low → high): ctx.env_vars → action.certs_vars → action.cfg scalars
def build-resolve-ctx [ctx: record, action: record]: nothing -> record {
    let base_vars  = ($ctx    | get --optional env_vars   | default {})
    let certs_vars = ($action | get --optional certs_vars | default {})
    let cfg        = ($action | get --optional cfg        | default {})
    let cfg_vars   = ($cfg | columns | where {|k|
        let v = ($cfg | get --optional $k)
        let t = ($v | describe)
        not ($t | str starts-with record) and not ($t | str starts-with list)
    } | reduce --fold {} { |k, acc|
        $acc | insert ($k | str upcase) ($cfg | get --optional $k | default "" | into string)
    })

    let merged   = ($base_vars | merge $certs_vars | merge $cfg_vars)
    let key_bits = ($merged | get --optional KEY_BITS | default "4096")
    {
        env_vars: $merged
        key_bits: $key_bits
    }
}

# Escape special regex characters in a plain string.
def regex-escape []: string -> string {
    str replace --all "." "\\."
    | str replace --all "*" "\\*"
    | str replace --all "+" "\\+"
    | str replace --all "?" "\\?"
    | str replace --all "(" "\\("
    | str replace --all ")" "\\)"
    | str replace --all "[" "\\["
    | str replace --all "]" "\\]"
    | str replace --all "{" "\\{"
    | str replace --all "}" "\\}"
    | str replace --all "|" "\\|"
    | str replace --all "^" "\\^"
    | str replace --all "$" "\\$"
}
