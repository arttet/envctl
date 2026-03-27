#!/usr/bin/env nu
# ==============================================================================
# tests/unit/parser_test.nu — Unit tests for src/engine/parser.nu
#
# Run directly:  nu tests/unit/parser_test.nu
# Via runner:    nu run_tests.nu --file tests/unit/parser_test.nu
# ==============================================================================

use std assert

use ../../src/engine/parser.nu [build-certs-vars]

# ---------------------------------------------------------------------------
# build-certs-vars — scalar [certs] fields become substitution variables
# ---------------------------------------------------------------------------

def test_certs_vars_empty []: any -> any {
    let r = (build-certs-vars { certs: {} })
    assert equal ($r | columns | length) 0
}

def test_certs_vars_scalar_string [] {
    let r = (build-certs-vars { certs: { organization: "My Org" } })
    assert equal $r.ORGANIZATION "My Org"
}

def test_certs_vars_scalar_int [] {
    let r = (build-certs-vars { certs: { key_bits: 4096 } })
    assert equal $r.KEY_BITS "4096"
}

def test_certs_vars_upcases_keys [] {
    let r = (build-certs-vars { certs: { country: "US" } })
    assert ($r has COUNTRY)
    assert not ($r has country)
}

def test_certs_vars_skips_record_fields [] {
    # Record fields = cert declarations — must not become variables
    let r = (build-certs-vars {
        certs: {
            organization: "My Org"
            root: { config_template: "infra/certs/root.cnf.tmpl" }
        }
    })
    assert ($r has ORGANIZATION)
    assert not ($r has ROOT)
}

def test_certs_vars_multiple_scalars [] {
    let r = (build-certs-vars {
        certs: {
            tool:         "openssl"
            key_bits:     4096
            organization: "Acme"
            country:      "US"
        }
    })
    assert equal ($r | columns | length) 4
    assert equal $r.TOOL         openssl
    assert equal $r.KEY_BITS     "4096"
    assert equal $r.ORGANIZATION Acme
    assert equal $r.COUNTRY      US
}

def test_certs_vars_no_certs_section [] {
    # Must not crash when [certs] is absent
    let r = (build-certs-vars {})
    assert equal ($r | columns | length) 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main [] {
    print parser_test.nu
    mut passed = 0
    mut failed = 0

    let tests = [
        [name fn];
        [test_certs_vars_empty           { test_certs_vars_empty }]
        [test_certs_vars_scalar_string   { test_certs_vars_scalar_string }]
        [test_certs_vars_scalar_int      { test_certs_vars_scalar_int }]
        [test_certs_vars_upcases_keys    { test_certs_vars_upcases_keys }]
        [test_certs_vars_skips_record_fields { test_certs_vars_skips_record_fields }]
        [test_certs_vars_multiple_scalars { test_certs_vars_multiple_scalars }]
        [test_certs_vars_no_certs_section { test_certs_vars_no_certs_section }]
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
        return (error make --unspanned { msg: "parser test failed" })
    }
}
