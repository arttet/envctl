# ==============================================================================
# language/keywords.nu — Reserved words registry for the envctl language.
#
# Single source of truth for all reserved identifiers.
# Parser, validator, grammar, and registry all import from here.
# Never hardcode reserved strings elsewhere.
#
# To add a new reserved word:
#   1. Add a const here
#   2. Add it to the appropriate export def below
#   3. Update grammar.nu or parser.nu if it affects token parsing
# ==============================================================================

# ---------------------------------------------------------------------------
# Plugin entry points
# ---------------------------------------------------------------------------
export const KEYWORD_MANIFEST = "manifest"

# ---------------------------------------------------------------------------
# Top-level .envctl.toml section keys
# ---------------------------------------------------------------------------
export const KEYWORD_SCHEMA = "schema"
export const KEYWORD_PROVIDERS = "providers"
export const KEYWORD_GENERATORS = "generators"
export const KEYWORD_SECRETS = "secrets"
export const KEYWORD_ENVFILE = "envfile"
export const KEYWORD_CERTS = "certs"

# ---------------------------------------------------------------------------
# Token grammar — prefixes reserved inside {{ }}
# ---------------------------------------------------------------------------
export const KEYWORD_TOKEN_SECRET = "secret"
export const KEYWORD_TOKEN_PROVIDER = "provider"

# ---------------------------------------------------------------------------
# Secrets section — service keys, not secret declarations
# ---------------------------------------------------------------------------
export const SECRETS_SERVICE_KEYS = [base_dir, excluded]

# ---------------------------------------------------------------------------
# Profile names
# ---------------------------------------------------------------------------
export const PROFILE_ENVFILE = "envfile"
export const PROFILE_SECRETS = "secrets"
export const PROFILE_CERTS = "certs"
export const PROFILE_ALL = "all"
export const PROFILES = [envfile, secrets, certs, all]

# ---------------------------------------------------------------------------
# State and lock
# ---------------------------------------------------------------------------
export const KEYWORD_AUDIT = "audit"

# ---------------------------------------------------------------------------
# Accessors
# ---------------------------------------------------------------------------
@example "Get plugin entry points" { plugin-entry-points }
export def plugin-entry-points [] {
    [
        $KEYWORD_MANIFEST
    ]
}

@example "Get config keys" { config-keys }
export def config-keys [] {
    [
        $KEYWORD_SCHEMA
        $KEYWORD_PROVIDERS
        $KEYWORD_GENERATORS
        $KEYWORD_SECRETS
        $KEYWORD_ENVFILE
        $KEYWORD_CERTS
    ]
}

@example "Get token prefixes" { token-prefixes }
export def token-prefixes [] {
    [$KEYWORD_TOKEN_SECRET, $KEYWORD_TOKEN_PROVIDER]
}

@example "Get profiles" { profiles }
export def profiles [] {
    $PROFILES
}

@example "Get secrets service keys" { secrets-service-keys }
export def secrets-service-keys [] {
    $SECRETS_SERVICE_KEYS
}

@example "Check valid profile" { is-valid-profile envfile }
@example "Check invalid profile" { is-valid-profile unknown }
export def is-valid-profile [profile: string] {
    $profile in $PROFILES
}
