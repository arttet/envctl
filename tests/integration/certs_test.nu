#!/usr/bin/env nu
# ==============================================================================
# tests/integration/certs_test.nu — Integration tests for certs generation
# ==============================================================================

use std assert

def test_certs_chain_generation [] {
    let old_pwd = $env.PWD
    let repo_root = $env.PWD
    let envctl_path = ($repo_root | path join envctl.nu)
    let tmp = (mktemp --directory)

    let root_tmpl = ($repo_root | path join infra/certs/root-ca.cnf.tmpl | path expand | str replace --all \ /)
    let leaf_tmpl = ($repo_root | path join infra/certs/leaf.cnf.tmpl | path expand | str replace --all \ /)

    try {
        cd $tmp

        # 1. Config with a root CA and a leaf cert
        (
            "[providers]\n"
            + "enabled = [\"certs\"]\n\n"
            + "[certs]\n"
            + "organization = \"Test Org\"\n"
            + "key_bits = 4096\n"
            + "country = \"US\"\n\n"
            + $"[certs.my-root]\n"
            + "common_name = \"Test Root CA\"\n"
            + $"config_template = \"($root_tmpl)\"\n"
            + "days = 365\n"
            + "options = { file = { cert = \"root.crt\", key = \"root.key\" } }\n\n"
            + $"[certs.my-leaf]\n"
            + "common_name = \"test-leaf.local\"\n"
            + "extended_key_usage = \"serverAuth, clientAuth\"\n"
            + "subject_alt_name = \"DNS:test-leaf.local\"\n"
            + "signed_by = \"my-root\"\n"
            + $"config_template = \"($leaf_tmpl)\"\n"
            + "options = { file = { cert = \"leaf.crt\", key = \"leaf.key\" } }\n"
        ) | save ".envctl.toml"

        # 2. Generate
        nu $envctl_path envctl certs generate

        # 3. Assert
        assert ("root.crt" | path exists)
        assert ("root.key" | path exists)
        assert ("leaf.crt" | path exists)
        assert ("leaf.key" | path exists)

        # 4. Check if leaf is signed by root (openssl check if available)
        if (which openssl | is-not-empty) {
            let res = (openssl verify -CAfile root.crt leaf.crt | complete)
            assert equal $res.exit_code 0
        }

        cd $old_pwd
        rm --recursive $tmp
    } catch {|err|
        cd $old_pwd
        rm --recursive $tmp
        error make {msg: $err.msg}
    }
}

def main [] {
    print certs_test.nu
    mut passed = 0
    mut failed = 0

    let tests = [
        [name fn];
        [test_certs_chain_generation { test_certs_chain_generation }]
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
        return (error make --unspanned { msg: "certs test failed" })
    }
}
