#!/usr/bin/env nu
# ==============================================================================
# tests/integration/secrets_test.nu — Integration tests for secrets management
# ==============================================================================

use std assert

def run-envctl [envctl_path: string, args: list<string>] {
    ^nu $envctl_path ...$args
}

def test_secrets_rotate_all [] {
    let old_pwd = $env.PWD
    let repo_root = $env.PWD
    let envctl_path = ($repo_root | path join "envctl.nu")
    let tmp = (mktemp -d)

    try {
        cd $tmp

        # 1. Init project with a secret
        (
            "[providers]\n"
            + "enabled = [\"password\"]\n\n"
            + "[secrets]\n"
            + "base_dir = \".\"\n\n"
            + "[secrets.MY_PASS]\n"
            + "value_source = \"{{ provider:password.generate-password }}\"\n"
            + "targets = [\"file\"]\n"
            + "options = { file = { path = \"mypass.txt\" } }\n"
        ) | save ".envctl.toml"

        # 2. Generate initially
        run-envctl $envctl_path ["envctl", "secrets", "generate"] | ignore
        let val1 = (open --raw "mypass.txt")
        assert not ($val1 | is-empty)

        # 3. Rotate all
        run-envctl $envctl_path ["envctl", "secrets", "rotate-all"] | ignore

        # 4. Assert
        let val2 = (open --raw "mypass.txt")
        assert not ($val1 == $val2)

        let backups = (glob "mypass.txt.bak_*")
        assert ($backups | is-not-empty)

        cd $old_pwd
        rm -rf $tmp
    } catch { |err|
        cd $old_pwd
        rm -rf $tmp
        error make {msg: $err.msg}
    }
}

def main [] {
    print "secrets_test.nu"
    mut passed = 0
    mut failed = 0

    let tests = [
        [name fn];
        ["test_secrets_rotate_all" { test_secrets_rotate_all }]
    ]

    for row in $tests {
        let ok = (try {
            do $row.fn
            true
        } catch { |err|
            print $"  ✗ ($row.name): ($err.msg)"
            false
        })

        if $ok {
            print $"  ✓ ($row.name)"
            $passed = $passed + 1
        } else {
            $failed = $failed + 1
        }
    }

    print $"\n  ($passed) passed, ($failed) failed"
    if $failed > 0 {
        return (error make --unspanned { msg: "secrets test failed" })
    }
}
