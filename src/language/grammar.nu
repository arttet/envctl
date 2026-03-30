# ==============================================================================
# language/grammar.nu — Token grammar parser for {{ }} substitutions.
#
# Formal grammar:
#   token         ::= "{{" SP? expr SP? "}}"
#   expr          ::= secret_expr | provider_expr | var_expr
#   secret_expr   ::= "secret:" IDENT
#   provider_expr ::= "provider:" IDENT "." IDENT
#   var_expr      ::= IDENT
#   IDENT         ::= [a-zA-Z_][a-zA-Z0-9_.-]*
#
# Rules:
#   - Unresolved token = hard error (not silent empty string)
#   - No new token types without updating keywords.nu AND this file first
#   - {{ VAR | filter }} is reserved syntax — not implemented
#
# Also handles:
#   - parse .env.example → token list  (was: template/tokenizer.nu)
#   - parse .env string  → key→value record  (shared by ctx.nu + diff.nu)
# ==============================================================================

use ./keywords.nu [KEYWORD_TOKEN_SECRET, KEYWORD_TOKEN_PROVIDER]

# Parse a string and extract all {{ }} tokens as a list of classified records.
@example "Parse var token" { parse-tokens "mysql://{{ DB_USER }}@{{ DB_HOST }}" }
@example "Parse secret token" { parse-tokens "{{ secret:DB_PASS_FILE }}" }
@example "Parse provider token" { parse-tokens "{{ provider:git.top-level-dir }}" }
@example "Parse empty string" { parse-tokens "" }
export def parse-tokens [input: string] {
    let pattern = '\{\{\s*([^}]+?)\s*\}\}'
    let matches = ($input | parse --regex $pattern)

    ($matches | each { |row|
        let raw_expr = ($row.capture0 | str trim)
        classify-expr $raw_expr
    })
}

# Classify a raw expression string into a typed token record.
@example "Classify var" { classify-expr DB_HOST }
@example "Classify secret" { classify-expr secret:DB_PASS_FILE }
@example "Classify provider" { classify-expr provider:git.top-level-dir }
export def classify-expr [expr: string] {

    let secret_prefix = $"($KEYWORD_TOKEN_SECRET):"
    let provider_prefix = $"($KEYWORD_TOKEN_PROVIDER):"

    if ($expr | str starts-with $secret_prefix) {
        let ident = ($expr | str replace $secret_prefix "" | str trim)
        {
            type: secret
            ident: $ident
            raw: $expr
        }
    } else if ($expr | str starts-with $provider_prefix) {
        let rest = ($expr | str replace $provider_prefix "" | str trim)
        let parts = ($rest | split row .)
        if ($parts | length) < 2 {
            error make {
                msg: $"[grammar] invalid provider token '($expr)' — expected provider:NAME.FN"
            }
        }

        {
            type: provider
            name: ($parts | first)
            fn: ($parts | last)
            raw: $expr
        }

    } else if ($expr | str contains "|") {
        error make {
            msg: $"[grammar] filter syntax '{{ ($expr) }}' is reserved — not yet implemented"
        }
    } else {
        {
            type: var
            ident: $expr
            raw: $expr
        }
    }
}

# Check if a string contains any unresolved {{ }} tokens.
@example "Has unresolved — true" { has-unresolved "hello {{ WORLD }}" }
@example "Has unresolved — false" { has-unresolved "hello world" }
export def has-unresolved [input: string] {
    $input | str contains "{{"
}

# Extract all plain variable names from {{ IDENT }} tokens only.
# Excludes secret and provider tokens.
@example "Extract var names" { extract-var-names "mysql://{{ DB_USER }}:{{ secret:PASS }}@{{ DB_HOST }}" }
@example "Extract var names from empty string" { extract-var-names "" }
export def extract-var-names [input: string] {
    parse-tokens $input | where type == var | get ident
}

# Resolve all {{ }} tokens in a string using the provided context.
# Hard error if any token cannot be resolved.
@example "Resolve var token" { resolve "hello {{ NAME }}" { env_vars: { NAME: world } secrets_root: . providers: {} } }
@example "Resolve empty string" { resolve "" { env_vars: {}, secrets_root: ., providers: {} } }
export def resolve [input: string, ctx: record] {
    let pattern = '\{\{\s*([^}]+?)\s*\}\}'
    mut result = $input

    while ($result | str contains "{{") {
        let match = ($result | parse --regex $pattern | get --optional 0?)
        if $match == null {
            break
        }

        let raw_expr = ($match | get capture0 | str trim)
        let token = (classify-expr $raw_expr)
        let value = (resolve-token $token $ctx)
        let escaped = ($raw_expr | regex-escape)
        let full_match = $"\\{\\{\\s*($escaped)\\s*\\}\\}"

        $result = ($result | str replace --regex $full_match $value)
    }

    $result
}

# Resolve a single classified token to its string value.
# Hard error if token cannot be resolved.
@example "Resolve var token" { resolve-token {type: var, ident: DB_HOST, raw: DB_HOST} { env_vars: { DB_HOST: localhost } secrets_root: . providers: {} } }
export def resolve-token [token: record, ctx: record] {
    let env_vars = ($ctx | get --optional env_vars | default {})
    let secrets_root = ($ctx | get --optional secrets_root | default .)
    let providers = ($ctx | get --optional providers | default {})

    match $token.type {
        "var" => {
            let val = ($env_vars | get --optional $token.ident | default "")
            if ($val | is-empty) {
                error make {
                    msg: $"[grammar] unresolved variable '($token.ident)' — not found in env_vars"
                }
            }

            $val
        }
        "secret" => {
            let secrets_paths = ($ctx | get --optional secrets_paths | default {})

            # Resolve file path: prefer secrets_paths (cross-secret reference by key),
            # fall back to env_vars[IDENT] as a file path (Docker _FILE pattern).
            let from_plan = ($secrets_paths | get --optional $token.ident | default "")
            let file_path = if ($from_plan | is-not-empty) {
                $from_plan | path expand
            } else {
                let file_path_raw = ($env_vars | get --optional $token.ident | default "")
                if ($file_path_raw | is-empty) {
                    error make {
                        msg: $"[grammar] '{{ secret:($token.ident) }}' — not in secrets plan and env var '($token.ident)' not set"
                    }
                }
                $secrets_root | path join ($file_path_raw | str trim --left --char /)
            }

            if not ($file_path | path exists) {
                error make {
                    msg: $"[grammar] '{{ secret:($token.ident) }}' — file not found: ($file_path)"
                }
            }

            open --raw $file_path | str trim
        }
        "provider" => {
            let provider = ($providers | get --optional $token.name)
            if $provider == null {
                error make {
                    msg: $"[grammar] '{{ provider:($token.name).($token.fn) }}' — provider '($token.name)' not loaded"
                }
            }

            let resolve_map = ($provider | get --optional resolve | default {})
            let fn_closure = ($resolve_map | get --optional $token.fn)
            if $fn_closure == null {
                let registered = ($resolve_map | columns | str join ", ")
                error make {
                    msg: $"[grammar] '{{ provider:($token.name).($token.fn) }}' — fn '($token.fn)' not in manifest.resolve — registered: ($registered)"
                }
            }

            do $fn_closure $ctx
        }
        _ => {
            error make {
                msg: $"[grammar] unknown token type '($token.type)' — this is a bug"
            }
        }
    }
}

# Tokenize raw .env.example text into a structured line list.
# Pure — no file I/O, no side effects.
#
# Each line becomes one of:
#   { kind: "comment", raw: "# ..." }
#   { kind: "blank",   raw: "" }
#   { kind: "var",     key: "DB_HOST", raw_value: "...", tokens: [...] }
@example "Tokenize empty template" { tokenize-env "" }
@example "Tokenize simple template" { tokenize-env "# comment\nDB_HOST=localhost\nDB_PORT={{ DB_PORT }}" }
@example "Tokenize provider token" { tokenize-env "GIT_ROOT={{ provider:git.top-level-dir }}" }
export def tokenize-env [raw: string] {
    $raw | lines | each {|line|
        let trimmed = ($line | str trim)

        if ($trimmed | is-empty) {
            {
                kind: blank, raw: $line
            }
        } else if ($trimmed | str starts-with "#") {
            {
                kind: comment, raw: $line
            }
        } else {
            let parts  = ($line | split row "=" | collect)
            let key    = ($parts | first | str trim)
            let val    = ($parts | skip 1 | str join "=")
            let tokens = (parse-tokens $val)

            {
                kind: var, key: $key, raw_value: $val, tokens: $tokens
            }
        }
    }
}

# Extract all variable keys from a tokenized .env.example.
@example "Extract keys from empty list" { [] | extract-env-keys }
@example "Extract keys from tokenized" { [ { kind: var key: DB_HOST raw_value: localhost tokens: [] } { kind: comment, raw: "# comment" } ] | extract-env-keys }
export def extract-env-keys [] {
    where kind == var | get key
}

# Extract generator keys needed for resolution —
# var-type token idents + keys that have provider/secret tokens.
@example "Extract needed keys from empty" { [] | extract-needed-keys }
@example "Extract needed keys" { [ { kind: var, key: A, raw_value: "", tokens: [ { type: var, ident: B } ] } ] | extract-needed-keys }
def extract-needed-keys [] {
    where kind == var | each {|line|
        $line.tokens | each {|t|
            match $t.type {
                "var"      => { $t.ident }
                "provider" => { $line.key }
                "secret"   => { $line.key }
                _          => { [] }
            }
        }
    } | flatten | uniq
}

# Parse raw .env content (string) into a flat key→value record.
# Skips blank lines and comments. Values preserve everything after the first `=`.
@example "Parse env string" { "FOO=bar\nBAZ=qux" | parse-env-string }
@example "Parse env string with comment" { "# comment\nFOO=bar" | parse-env-string }
@example "Parse env string with value containing =" { "URL=http://x?a=1" | parse-env-string }
export def parse-env-string [] {
    $in | lines | where {|line|
        let t = ($line | str trim)
        ($t | is-not-empty) and (not ($t | str starts-with "#"))
    } | reduce --fold {} {|line, acc|
        let parts = ($line | split row "=" | collect)
        let key   = ($parts | first | str trim)
        let val   = ($parts | skip 1 | str join "=")
        $acc | insert $key $val
    }
}

def regex-escape [] {
    str replace --all . \. | str replace --all '*' '\*' | str replace --all + \+ | str replace --all '?' '\?' | str replace --all '(' '\(' | str replace --all ')' '\)' | str replace --all '[' '\[' | str replace --all ']' '\]' | str replace --all '{' '\{' | str replace --all '}' '\}' | str replace --all '|' '\|' | str replace --all ^ \^ | str replace --all '$' \$
}
