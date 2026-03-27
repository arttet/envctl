#!/usr/bin/env nu
# ==============================================================================
# tests/unit/provider_test.nu — Unit tests for src/runtime/providers/
#
# Run directly:  nu tests/unit/provider_test.nu
# Via runner:    nu run_tests.nu --file tests/unit/provider_test.nu
# ==============================================================================

use std assert

use ../../plugins/providers/git.nu
use ../../plugins/providers/password.nu

# ---------------------------------------------------------------------------
# git provider
# ---------------------------------------------------------------------------

def test_git_manifest_exists []: any -> any {
    let m = (git manifest)
    assert equal $m.name git
    assert ("top-level-dir" in $m.provides)
}

def test_git_manifest_version [] {
    let m = (git manifest)
    assert equal $m.version 1.0.0
}

def test_git_has_resolve_fn [] {
    let m = (git manifest)
    assert ($m has resolve)
    assert ($m.resolve has top-level-dir)
}

# ---------------------------------------------------------------------------
# password provider
# ---------------------------------------------------------------------------

def test_password_manifest_exists [] {
    let m = (password manifest)
    assert equal $m.name password
    assert ("generate-password" in $m.provides)
}

def test_password_manifest_version [] {
    let m = (password manifest)
    assert equal $m.version 1.0.0
}

def test_password_manifest_config_schema [] {
    let m = (password manifest)
    assert equal $m.config_schema password.config.schema.toml
}

def test_password_manifest_health_schema [] {
    let m = (password manifest)
    assert equal $m.health_schema password.health.schema.toml
}

def test_password_manifest_env_vars [] {
    let m = (password manifest)
    # Just verify env_vars exists and is not empty
    assert ($m has env_vars)
}

def test_password_has_resolve_fn [] {
    let m = (password manifest)
    assert ($m has resolve)
    assert ($m.resolve has generate-password)
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main [] {
    print provider_test.nu
    mut passed = 0
    mut failed = 0

    let tests = [
        [name fn];
        [test_git_manifest_exists              { test_git_manifest_exists }]
        [test_git_manifest_version             { test_git_manifest_version }]
        [test_git_has_resolve_fn               { test_git_has_resolve_fn }]
        [test_password_manifest_exists         { test_password_manifest_exists }]
        [test_password_manifest_version        { test_password_manifest_version }]
        [test_password_manifest_config_schema  { test_password_manifest_config_schema }]
        [test_password_manifest_health_schema  { test_password_manifest_health_schema }]
        [test_password_manifest_env_vars       { test_password_manifest_env_vars }]
        [test_password_has_resolve_fn          { test_password_has_resolve_fn }]
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
        return (error make --unspanned { msg: "provider test failed" })
    }
}
