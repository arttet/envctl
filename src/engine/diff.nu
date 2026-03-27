# ==============================================================================
# engine/diff.nu — Drift detection between resolved plan and disk state.
#
# Compares tokenized .env.example template against current .env on disk.
# Used by: envctl envfile diff, envctl health --profile envfile
#
# Absorbs: language/template/render.nu (diff function)
#
# Pure — no file writes, no side effects.
# ==============================================================================

use ../language/grammar.nu [tokenize-env, extract-env-keys, parse-env-string]

# Detect differences (drift) between .env template tokens and actual environment variables.
#
# Returns:
#   { added: list<string>, removed: list<string> }
#   added   — keys in template but missing from .env
#   removed — keys in .env but not in template
@example "Diff empty template against empty env" { diff-env [] {} }
@example "Diff template against matching env" { diff-env [{ kind: "var", key: "DB_HOST", raw_value: "", tokens: [] }] { DB_HOST: "localhost" } }
@example "Diff template with missing env key" { diff-env [{ kind: "var", key: "DB_HOST", raw_value: "", tokens: [] }, { kind: "var", key: "DB_PORT", raw_value: "", tokens: [] }] { DB_HOST: "localhost" } }
export def diff-env [
    tokens:   list<record>   # output of grammar tokenize-env
    env_vars: record         # current .env key→value map
]: nothing -> record {
    let template_keys = ($tokens | where kind == "var" | get key)

    let env_keys = ($env_vars | columns)
    {
        added: ($template_keys | where {|k| not ($k in $env_keys)})
        removed: ($env_keys | where {|k| not ($k in $template_keys)})
    }
}

# Load .env file from disk and compute drift against template file.
# Convenience wrapper used by health checks.
@example "Diff files" { diff-files ".env.example" ".env" }
export def diff-files [
    template_path: string  # path to .env.example
    env_path:      string   # path to current .env
]: nothing -> record {
    if not ($template_path | path exists) {
        return {
            added: []
            removed: []
            error: $"template not found: ($template_path)"
        }
    }

    let tokens = (tokenize-env (open --raw $template_path))
    let env_vars = if ($env_path | path exists) {
        open --raw $env_path | parse-env-string
    } else {
        {}
    }

    diff-env $tokens $env_vars
}

# Returns true if there is no drift.
@example "Is in sync — true" { is-in-sync { added: [], removed: [] } }
@example "Is in sync — false" { is-in-sync { added: ["DB_HOST"], removed: [] } }
export def is-in-sync [drift: record] {
    ($drift.added | is-empty) and ($drift.removed | is-empty)
}
