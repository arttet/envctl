#!/usr/bin/env nu
# ==============================================================================
# tests/unit/grammar_test.nu — Unit tests for src/language/grammar.nu
#
# Run directly:  nu tests/unit/grammar_test.nu
# Via runner:    nu run_tests.nu --file tests/unit/grammar_test.nu
# ==============================================================================

use std assert

use ../../src/language/grammar.nu [
    parse-tokens
    classify-expr
    resolve
    tokenize-env
    extract-env-keys
    has-unresolved
]

# ---------------------------------------------------------------------------
# parse-tokens
# ---------------------------------------------------------------------------

def test_parse_tokens_var []: any -> any {
    let r = (parse-tokens "{{ DB_HOST }}")
    assert equal ($r | length) 1
    assert equal $r.0.type var
    assert equal $r.0.ident DB_HOST
}

def test_parse_tokens_provider [] {
    let r = (parse-tokens "{{ provider:git.top-level-dir }}")
    assert equal ($r | length) 1
    assert equal $r.0.type provider
    assert equal $r.0.name git
    assert equal $r.0.fn top-level-dir
}

def test_parse_tokens_secret [] {
    let r = (parse-tokens "{{ secret:DB_PASS_FILE }}")
    assert equal ($r | length) 1
    assert equal $r.0.type secret
    assert equal $r.0.ident DB_PASS_FILE
}

def test_parse_tokens_multiple [] {
    let r = (parse-tokens "mysql://{{ USER }}:{{ secret:PASS_FILE }}@{{ HOST }}")
    assert equal ($r | length) 3
    assert equal $r.0.type var
    assert equal $r.1.type secret
    assert equal $r.2.type var
}

def test_parse_tokens_no_spaces [] {
    let r = (parse-tokens "{{DB_HOST}}")
    assert equal ($r | length) 1
    assert equal $r.0.type var
    assert equal $r.0.ident DB_HOST
}

# ---------------------------------------------------------------------------
# classify-expr
# ---------------------------------------------------------------------------

def test_classify_var [] {
    let r = (classify-expr DB_HOST)
    assert equal $r.type var
    assert equal $r.ident DB_HOST
}

def test_classify_provider [] {
    let r = (classify-expr provider:password.generate-password)
    assert equal $r.type provider
    assert equal $r.name password
    assert equal $r.fn generate-password
}

def test_classify_secret [] {
    let r = (classify-expr secret:MY_SECRET_FILE)
    assert equal $r.type secret
    assert equal $r.ident MY_SECRET_FILE
}

# ---------------------------------------------------------------------------
# resolve
# ---------------------------------------------------------------------------

def test_resolve_var [] {
    let ctx = {
    env_vars: {NAME: world}
    secrets_root: .
    providers: {}
}
    assert equal (resolve "hello {{ NAME }}" $ctx) "hello world"
}

def test_resolve_multiple_vars [] {
    let ctx = {
    env_vars: {HOST: localhost, PORT: "5432"}
    secrets_root: .
    providers: {}
}
    assert equal (resolve "{{ HOST }}:{{ PORT }}" $ctx) localhost:5432
}

def test_resolve_unresolved_errors [] {
    let ctx = {env_vars: {}, secrets_root: ., providers: {}}
    let failed = (try { resolve "{{ MISSING }}" $ctx; false } catch { true })
    assert $failed
}

def test_resolve_secret_from_secrets_paths [] {
    let tmp_dir = (mktemp -d)
    let secret_file = ($tmp_dir | path join "secret")
    "s3cr3t" | save --force $secret_file
    let ctx = {
        env_vars: {}
        secrets_root: .
        providers: {}
        secrets_paths: { MY_PASS_FILE: $secret_file }
    }
    let result = (resolve "prefix:{{ secret:MY_PASS_FILE }}:suffix" $ctx)
    rm --recursive --force $tmp_dir
    assert equal $result "prefix:s3cr3t:suffix"
}

def test_resolve_secret_not_in_plan_errors [] {
    # IDENT not in secrets_paths and not in env_vars → error
    let ctx = {env_vars: {}, secrets_root: ., providers: {}, secrets_paths: {}}
    let failed = (try { resolve "{{ secret:MISSING_FILE }}" $ctx; false } catch { true })
    assert $failed
}

# ---------------------------------------------------------------------------
# has-unresolved
# ---------------------------------------------------------------------------

def test_tokenize_env_comment [] {
    let r = (tokenize-env "# this is a comment")
    assert equal ($r | length) 1
    assert equal $r.0.kind comment
}

def test_tokenize_env_var [] {
    let r = (tokenize-env DB_HOST=localhost)
    assert equal ($r | length) 1
    assert equal $r.0.kind var
    assert equal $r.0.key DB_HOST
    assert equal $r.0.raw_value localhost
}

def test_tokenize_env_provider_token [] {
    let r = (tokenize-env "GIT_ROOT={{ provider:git.top-level-dir }}")
    assert equal $r.0.kind var
    assert equal ($r.0.tokens | length) 1
    assert equal $r.0.tokens.0.type provider
}

# ---------------------------------------------------------------------------
# extract-env-keys
# ---------------------------------------------------------------------------

def test_extract_env_keys [] {
    let keys = (tokenize-env "# comment\nDB_HOST=localhost\nDB_PORT=5432" | extract-env-keys)
    assert equal ($keys | length) 2
    assert ("DB_HOST" in $keys)
    assert ("DB_PORT" in $keys)
}

def test_extract_env_keys_skips_comments [] {
    let keys = (tokenize-env "# comment\nDB_HOST=localhost" | extract-env-keys)
    assert equal ($keys | length) 1
}

# ---------------------------------------------------------------------------
# Main — run all tests directly (no subprocess)
# ---------------------------------------------------------------------------

def main [] {
    print grammar_test.nu
    mut passed = 0
    mut failed = 0

    let tests = [
        [name fn];
        [test_parse_tokens_empty         { assert equal (parse-tokens "" | length) 0 }]
        [test_parse_tokens_no_tokens     { assert equal (parse-tokens "plain string" | length) 0 }]
        [test_parse_tokens_var           { test_parse_tokens_var }]
        [test_parse_tokens_provider      { test_parse_tokens_provider }]
        [test_parse_tokens_secret        { test_parse_tokens_secret }]
        [test_parse_tokens_multiple      { test_parse_tokens_multiple }]
        [test_parse_tokens_no_spaces     { test_parse_tokens_no_spaces }]
        [test_classify_var               { test_classify_var }]
        [test_classify_provider          { test_classify_provider }]
        [test_classify_secret            { test_classify_secret }]
        [test_resolve_empty              { assert equal (resolve "" { env_vars: {}, secrets_root: ".", providers: {} }) "" }]
        [test_resolve_no_tokens          { assert equal (resolve "plain string" { env_vars: {}, secrets_root: ".", providers: {} }) "plain string" }]
        [test_resolve_var                { test_resolve_var }]
        [test_resolve_multiple_vars      { test_resolve_multiple_vars }]
        [test_resolve_unresolved_errors           { test_resolve_unresolved_errors }]
        [test_resolve_secret_from_secrets_paths   { test_resolve_secret_from_secrets_paths }]
        [test_resolve_secret_not_in_plan_errors   { test_resolve_secret_not_in_plan_errors }]
        [test_has_unresolved_true        { assert (has-unresolved "hello {{ WORLD }}") }]
        [test_has_unresolved_false       { assert not (has-unresolved "hello world") }]
        [test_has_unresolved_empty       { assert not (has-unresolved "") }]
        [test_tokenize_env_empty         { assert equal (tokenize-env "" | length) 0 }]
        [test_tokenize_env_comment       { test_tokenize_env_comment }]
        [test_tokenize_env_var           { test_tokenize_env_var }]
        [test_tokenize_env_provider_token { test_tokenize_env_provider_token }]
        [test_extract_env_keys           { test_extract_env_keys }]
        [test_extract_env_keys_skips_comments { test_extract_env_keys_skips_comments }]
    ]

    for row in $tests {
        let ok = (try {
            do $row.fn
            true
        } catch {|err|
            print $"  ✗ ($row.name): ($err.msg)"
            false
        })

        if $ok {
            print $"  ✓ ($row.name)"
            $passed += 1
        } else {
            $failed += 1
        }
    }

    print $"\n  ($passed) passed, ($failed) failed"
    if $failed > 0 {
        return (error make --unspanned { msg: "grammar test failed" })
    }
}
