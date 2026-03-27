#!/usr/bin/env nu
# ==============================================================================
# tests/unit/lock_test.nu — Unit tests for src/state/lock.nu
#
# Run directly:  nu tests/unit/lock_test.nu
# Via runner:    nu run_tests.nu --file tests/unit/lock_test.nu
# ==============================================================================

use std assert

use ../../src/state/lock.nu [read-lock check-versions lock-status]

# ---------------------------------------------------------------------------
# read-lock
# ---------------------------------------------------------------------------

def test_read_lock_missing_file []: any -> any {
    # Non-existent lock file should return empty record
    let result = (read-lock .envctl.missing.lock)
    assert equal ($result | columns | length) 0
}

def test_check_versions_empty_lock [] {
    # Empty lock should not cause errors
    check-versions [] [] {}
    # If we reach here, no error was thrown
    true
}

def test_check_versions_matching [] {
    let manifests = [
        {name: "git", version: "1.0.0"}
    ]
    let lock = {
        providers: {git: {version: "1.0.0"}}
    }
    # Should not throw
    check-versions $manifests [] $lock
    true
}

def test_check_versions_mismatch [] {
    let manifests = [
        {
            name: "git",
            version: "2.0.0"
        }
    ]

    let lock = {
        providers: {git: {version: "1.0.0"}}
    }

    let error_thrown = (
        try {
            check-versions $manifests [] $lock
            false
        } catch {|err|
            $err.msg =~ "version mismatch"
        }
    )

    assert $error_thrown
}

# ---------------------------------------------------------------------------
# lock-status
# ---------------------------------------------------------------------------

def test_lock_status_empty [] {
    let result = (lock-status {})
    assert equal ($result | length) 0
}

def test_lock_status_with_providers [] {
    let lock = {
        providers: {
            git: {version: 1.0.0}
            password: {version: 1.0.0}
        }
    }
    let result = (lock-status $lock)
    assert equal ($result | length) 2

    let has_git = ($result | any {|r| $r.kind == provider and $r.name == git })
    assert $has_git
}

def test_lock_status_with_backends [] {
    let lock = {
        backends: {
            file: {version: 1.0.0}
        }
    }

    let result = (lock-status $lock)
    assert equal ($result | length) 1
    assert equal $result.0.kind backend
    assert equal $result.0.name file
}

def test_lock_status_missing_version [] {
    # Missing version should show "?"
    let lock = {
        providers: {
            git: {}
        }
    }

    let result = (lock-status $lock)
    assert equal $result.0.version "?"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main [] {
    print lock_test.nu
    mut passed = 0
    mut failed = 0

    let tests = [
        [name fn];
        [test_read_lock_missing_file      { test_read_lock_missing_file }]
        [test_check_versions_empty_lock   { test_check_versions_empty_lock }]
        [test_check_versions_matching     { test_check_versions_matching }]
        [test_check_versions_mismatch     { test_check_versions_mismatch }]
        [test_lock_status_empty           { test_lock_status_empty }]
        [test_lock_status_with_providers  { test_lock_status_with_providers }]
        [test_lock_status_with_backends   { test_lock_status_with_backends }]
        [test_lock_status_missing_version { test_lock_status_missing_version }]
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
        return (error make --unspanned { msg: "lock test failed" })
    }
}
