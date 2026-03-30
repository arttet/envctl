#!/usr/bin/env nu
# ==============================================================================
# tests/unit/parser_test.nu — Unit tests for src/engine/parser.nu
#
# Run directly:  nu tests/unit/parser_test.nu
# Via runner:    nu run_tests.nu --file tests/unit/parser_test.nu
# ==============================================================================

use std assert

use ../../src/engine/parser.nu [build-certs-vars build-secret-nodes]

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
# build-secret-nodes — provider_options per-secret overrides
# ---------------------------------------------------------------------------

def test_secret_nodes_no_overrides [] {
    let nodes = (build-secret-nodes {
        secrets: {
            base_dir: "."
            MY_SECRET: { value_source: "{{ provider:password.generate-password }}", targets: ["file"] }
        }
    })
    assert equal ($nodes | length) 1
    assert equal ($nodes | first | get --optional provider_options | default {}) {}
}

def test_secret_nodes_length_override [] {
    let nodes = (build-secret-nodes {
        secrets: {
            base_dir: "."
            JWT_KEY: { value_source: "{{ provider:password.generate-password }}", targets: ["file"], length: 128 }
        }
    })
    let po = ($nodes | first | get --optional provider_options | default {})
    assert equal ($po | get --optional length | default 0) 128
    assert equal ($po | columns | length) 1
}

def test_secret_nodes_charset_override [] {
    let nodes = (build-secret-nodes {
        secrets: {
            base_dir: "."
            API_KEY: { value_source: "{{ provider:password.generate-password }}", targets: ["file"], charset: "hex" }
        }
    })
    let po = ($nodes | first | get --optional provider_options | default {})
    assert equal ($po | get --optional charset | default "") "hex"
    assert equal ($po | columns | length) 1
}

def test_secret_nodes_all_overrides [] {
    let nodes = (build-secret-nodes {
        secrets: {
            base_dir: "."
            PRIV_KEY: {
                value_source: "{{ provider:password.generate-password }}"
                targets: ["file"]
                length: 512
                charset: "hex"
                tool: "openssl"
            }
        }
    })
    let po = ($nodes | first | get --optional provider_options | default {})
    assert equal ($po | get --optional length  | default 0)  512
    assert equal ($po | get --optional charset | default "") "hex"
    assert equal ($po | get --optional tool    | default "") "openssl"
    assert equal ($po | columns | length) 3
}

def test_secret_nodes_no_secrets [] {
    let nodes = (build-secret-nodes { secrets: { base_dir: "." } })
    assert equal ($nodes | length) 0
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
        [test_certs_vars_empty                { test_certs_vars_empty }]
        [test_certs_vars_scalar_string        { test_certs_vars_scalar_string }]
        [test_certs_vars_scalar_int           { test_certs_vars_scalar_int }]
        [test_certs_vars_upcases_keys         { test_certs_vars_upcases_keys }]
        [test_certs_vars_skips_record_fields  { test_certs_vars_skips_record_fields }]
        [test_certs_vars_multiple_scalars     { test_certs_vars_multiple_scalars }]
        [test_certs_vars_no_certs_section     { test_certs_vars_no_certs_section }]
        [test_secret_nodes_no_overrides       { test_secret_nodes_no_overrides }]
        [test_secret_nodes_length_override    { test_secret_nodes_length_override }]
        [test_secret_nodes_charset_override   { test_secret_nodes_charset_override }]
        [test_secret_nodes_all_overrides      { test_secret_nodes_all_overrides }]
        [test_secret_nodes_no_secrets         { test_secret_nodes_no_secrets }]
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
