# ==============================================================================
# engine/queries.nu — Pure getters over AST record.
#
# No logic — only get --optional + sensible defaults.
# All functions accept an AST record produced by engine/parser.nu.
# Absorbs: config/queries.nu
# ==============================================================================

use ../core/constants.nu [DEFAULT_ENVFILE, DEFAULT_PATTERN, DEFAULT_SECRETS_DIR]

# Returns the generated .env file path.
@example "Get env-file from ast" { env-file { envfile: {file: .env, pattern: .env.example, excluded: [] } } }
export def env-file [ast: record] {
    $ast | get --optional envfile.file | default $DEFAULT_ENVFILE
}

# Returns the .env template path.
@example "Get template from ast" { template { envfile: {file: .env, pattern: .env.example, excluded: []} } }
export def template [ast: record] {
    $ast | get --optional envfile.pattern | default $DEFAULT_PATTERN
}

# Returns excluded keys from envfile section.
@example "Get excluded from ast" { excluded { envfile: {file: .env, pattern: .env.example, excluded: [DEBUG] } } }
export def excluded [ast: record] {
    $ast | get --optional envfile.excluded | default []
}

# Returns the base directory for secret files.
@example "Get secrets-root from ast" { secrets-root { cfg: {secrets: {base_dir: .} } } }
export def secrets-root [ast: record] {
    $ast | get --optional cfg.secrets.base_dir | default $DEFAULT_SECRETS_DIR
}

# Returns list of enabled provider names.
@example "Get enabled-providers from ast" { enabled-providers { cfg: { providers: {enabled: [] } } } }
export def enabled-providers [ast: record] {
    $ast | get --optional cfg.providers.enabled | default []
}

# Returns generator AST nodes.
@example "Get generators from empty ast" { generators {generators: [] } }
export def generators [ast: record] {
    $ast | get --optional generators | default []
}

# Returns generator AST nodes as key→resolved map.
@example "Get generators-map from empty ast" { generators-map {generators: [] } }
export def generators-map [ast: record] {
    generators $ast | reduce --fold {} {|g, acc| $acc | insert $g.key $g.raw }
}

# Returns secret AST nodes.
@example "Get secrets from empty ast" { secrets {secrets: [] } }
export def secrets [ast: record] {
    $ast | get --optional secrets | default []
}

# Returns cert AST nodes — topologically sorted by signed_by.
@example "Get certs from empty ast" { certs {certs: [] } }
export def certs [ast: record] {
    $ast | get --optional certs | default []
}

# Returns certs substitution vars — scalar fields from [certs] in UPPER_CASE.
# Available as {{ TOOL }}, {{ KEY_BITS }}, {{ ORGANIZATION }}, {{ COUNTRY }} in templates.
@example "Get certs-vars from empty ast" { certs-vars { certs_vars: {} } }
export def certs-vars [ast: record] {
    $ast | get --optional certs_vars | default {}
}

# Returns [certs] full config record (includes both scalars and cert declarations).
@example "Get certs-config from ast" { certs-config { cfg: { certs: { tool: openssl } } } }
export def certs-config [ast: record] {
    $ast | get --optional cfg.certs | default {}
}

# Returns provider config for a named provider.
@example "Get provider-cfg for password" { provider-cfg { providers: { password: { length: 32 } } } password }
export def provider-cfg [ast: record, name: string] {
    $ast | get --optional providers | default {} | get --optional $name | default {}
}
