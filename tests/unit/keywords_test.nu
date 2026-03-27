#!/usr/bin/env nu
# ==============================================================================
# tests/unit/keywords_test.nu — Unit tests for src/language/keywords.nu
#
# Run directly:  nu tests/unit/keywords_test.nu
# Via runner:    nu run_tests.nu --file tests/unit/keywords_test.nu
# ==============================================================================

use std assert

use ../../src/language/keywords.nu [
    config-keys
    token-prefixes
    profiles
    secrets-service-keys
    is-valid-profile
    PROFILES
    KEYWORD_CERTS
    KEYWORD_ENVFILE
    KEYWORD_SECRETS
    KEYWORD_PROVIDERS
    KEYWORD_GENERATORS
]

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

def test_config_keys_contains_all_sections []: any -> any {
    let keys = (config-keys)
    assert ("schema"     in $keys)
    assert ("providers"  in $keys)
    assert ("generators" in $keys)
    assert ("secrets"    in $keys)
    assert ("envfile"    in $keys)
    assert ("certs"      in $keys)
}

# ---------------------------------------------------------------------------
# token-prefixes
# ---------------------------------------------------------------------------

def test_token_prefixes [] {
    let p = (token-prefixes)
    assert ("secret"   in $p)
    assert ("provider" in $p)
}

# ---------------------------------------------------------------------------
# profiles fn
# ---------------------------------------------------------------------------

def test_profiles_fn [] {
    let p = (profiles)
    assert equal ($p | length) 4
    assert ("envfile" in $p)
    assert ("secrets" in $p)
    assert ("certs"   in $p)
    assert ("all"     in $p)
}

# ---------------------------------------------------------------------------
# secrets-service-keys
# ---------------------------------------------------------------------------

def test_secrets_service_keys [] {
    let keys = (secrets-service-keys)
    assert ("base_dir"  in $keys)
    assert ("excluded"  in $keys)
}

# ---------------------------------------------------------------------------
# is-valid-profile
# ---------------------------------------------------------------------------

def main [] {
    print keywords_test.nu
    mut passed = 0
    mut failed = 0

    let tests = [
        [name fn];
        [test_keyword_certs_value             { assert equal $KEYWORD_CERTS certs }]
        [test_keyword_envfile_value           { assert equal $KEYWORD_ENVFILE envfile }]
        [test_profiles_length                 { assert equal ($PROFILES | length) 4 }]
        [test_profiles_contains_envfile       { assert ("envfile" in $PROFILES) }]
        [test_profiles_contains_secrets       { assert ("secrets" in $PROFILES) }]
        [test_profiles_contains_certs         { assert ("certs"   in $PROFILES) }]
        [test_profiles_contains_all           { assert ("all"     in $PROFILES) }]
        [test_config_keys_contains_all_sections { test_config_keys_contains_all_sections }]
        [test_token_prefixes                  { test_token_prefixes }]
        [test_profiles_fn                     { test_profiles_fn }]
        [test_secrets_service_keys            { test_secrets_service_keys }]
        [test_is_valid_profile_envfile        { assert     (is-valid-profile envfile) }]
        [test_is_valid_profile_secrets        { assert     (is-valid-profile secrets) }]
        [test_is_valid_profile_certs          { assert     (is-valid-profile certs) }]
        [test_is_valid_profile_all            { assert     (is-valid-profile all) }]
        [test_is_valid_profile_invalid        { assert not (is-valid-profile unknown) }]
        [test_is_valid_profile_empty          { assert not (is-valid-profile "") }]
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
        return (error make --unspanned { msg: "keywords test failed" })
    }
}
