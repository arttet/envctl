#!/usr/bin/env nu
# ==============================================================================
# tests/unit/schema_test.nu — Unit tests for src/schema/validate.nu
#
# Run directly:  nu tests/unit/schema_test.nu
# Via runner:    nu run_tests.nu --file tests/unit/schema_test.nu
# ==============================================================================

use std assert

use ../../src/schema/validate.nu [validate-schema apply-defaults]

# ---------------------------------------------------------------------------
# validate-schema
# ---------------------------------------------------------------------------

def test_validate_empty_record [] {
    # Empty record is valid for envctl.config.schema.toml as all fields have defaults
    validate-schema {} envctl.config.schema.toml
}

def test_validate_wrong_type [] {
    let cfg = {schema: 123} # schema should be string
    let ok = (try {
        validate-schema $cfg envctl.config.schema.toml
        true
    } catch {
        false
    })
    assert (not $ok)
}

def test_validate_invalid_enum [] {
    let cfg = {schema: v2} # schema enum is ["v1"]
    let ok = (try {
        validate-schema $cfg envctl.config.schema.toml
        true
    } catch {
        false
    })
    assert (not $ok)
}

def test_validate_correct_schema [] {
    let cfg = {schema: v1}
    validate-schema $cfg envctl.config.schema.toml
}

def test_validate_unknown_field [] {
    let cfg = {schema: v1, unknown_field: value}
    # Should either warn or ignore unknown fields - currently ignores
    validate-schema $cfg envctl.config.schema.toml
}

# ---------------------------------------------------------------------------
# apply-defaults
# ---------------------------------------------------------------------------

def test_apply_defaults_empty [] {
    let result = (apply-defaults {} envctl.config.schema.toml)
    assert equal ($result | get schema) v1
}

def test_apply_defaults_preserves_values [] {
    let cfg = {schema: v1, custom: value}
    let result = (apply-defaults $cfg envctl.config.schema.toml)
    assert equal ($result | get custom) value
    assert equal ($result | get schema) v1
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main [] {
    print schema_test.nu
    mut passed = 0
    mut failed = 0

    let tests = [
        [name fn];
        [test_validate_empty_record        { test_validate_empty_record }]
        [test_validate_wrong_type          { test_validate_wrong_type }]
        [test_validate_invalid_enum        { test_validate_invalid_enum }]
        [test_validate_correct_schema      { test_validate_correct_schema }]
        [test_validate_unknown_field       { test_validate_unknown_field }]
        [test_apply_defaults_empty         { test_apply_defaults_empty }]
        [test_apply_defaults_preserves_values { test_apply_defaults_preserves_values }]
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
        return (error make --unspanned { msg: "schema test failed" })
    }
}
