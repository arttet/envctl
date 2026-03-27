#!/usr/bin/env nu
# ==============================================================================
# tests/unit/backend_test.nu — Unit tests for src/runtime/backends/file.nu
#
# Run directly:  nu tests/unit/backend_test.nu
# Via runner:    nu run_tests.nu --file tests/unit/backend_test.nu
# ==============================================================================

use std assert

use ../../plugins/backends/file.nu [manifest exists-secret]

# ---------------------------------------------------------------------------
# manifest
# ---------------------------------------------------------------------------

def test_manifest_structure []: any -> any {
    let m = (manifest)
    # Just verify manifest is a record with expected structure
    assert ($m has name)
    assert ($m has version)
    assert ($m has kind)
}

def test_manifest_required_fields [] {
    let m = (manifest)
    assert ($m has write_fn)
    assert ($m has read_fn)
    assert ($m has exists_fn)
    assert ($m has health_fn)
}

def test_manifest_provides [] {
    let m = (manifest)
    assert ("write-secret" in $m.provides)
    assert ("exists-secret" in $m.provides)
    assert ("health-secret" in $m.provides)
    assert ("read-secret" in $m.provides)
}

# ---------------------------------------------------------------------------
# exists-secret
# ---------------------------------------------------------------------------

def test_exists_secret_missing_file [] {
    let ctx = {secrets_root: /tmp/nonexistent}
    let result = (exists-secret $ctx MISSING_SECRET { path: "/tmp/nonexistent/missing" })
    assert equal $result false
}

def test_exists_secret_with_empty_options [] {
    let ctx = {secrets_root: .}
    # Non-existent file should return false
    let result = (exists-secret $ctx NONEXISTENT {})
    assert equal $result false
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main [] {
    print backend_test.nu
    mut passed = 0
    mut failed = 0

    let tests = [
        [name fn];
        [test_manifest_structure         { test_manifest_structure }]
        [test_manifest_required_fields   { test_manifest_required_fields }]
        [test_manifest_provides          { test_manifest_provides }]
        [test_exists_secret_missing_file { test_exists_secret_missing_file }]
        [test_exists_secret_with_empty_options { test_exists_secret_with_empty_options }]
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
        return (error make --unspanned { msg: "backend test failed" })
    }
}
