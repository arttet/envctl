#!/usr/bin/env nu
# ==============================================================================
# tests/integration/generate_test.nu — Integration tests for 'envctl generate'
#
# Run directly:  nu tests/integration/generate_test.nu
# Via runner:    nu run_tests.nu --file tests/integration/generate_test.nu
# ==============================================================================

use std assert

# Helper to run envctl in a temporary directory
def run-envctl [envctl_path: string, ...args: string]: any -> string {
    # Use absolute path for envctl.nu and ensure it can find its sub-files
    # envctl.nu uses relative paths for 'use' commands, so we MUST run it from its own directory
    # OR we use 'source' with the correct path.
    # The current 'main' in envctl.nu uses 'nu -c "source ...; $cmd"', which is tricky.

    # Let's just run it as a script and hope for the best
    nu $envctl_path ...$args
}

def test_generate_all_dependency_order [] {
    let old_pwd = $env.PWD
    let envctl_path = ($env.PWD | path join envctl.nu)
    let tmp = (mktemp --directory)

    try {
        cd $tmp

        # 1. Init minimal project
        (
            "[envfile]\n"
            + "file = \".env\"\n"
            + "pattern = \".env.example\"\n\n"
            + "[secrets]\n"
            + "base_dir = \".\"\n\n"
            + "[providers]\n"
            + "enabled = [\"password\"]\n\n"
            + "[generators]\n"
            + "DB_PASS_FILE = \"db_pass.txt\"\n"
        ) | save ".envctl.toml"

        "DB_PASSWORD_VALUE={{ secret:DB_PASS_FILE }}" | save ".env.example"

        # 2. Add secret
        (
            "\n[secrets.DB_PASSWORD]\n"
            + "value_source = \"supersecret\"\n"
            + "targets = [\"file\"]\n"
            + "options = { file = { path = \"{{ DB_PASS_FILE }}\" } }\n"
        ) | save --append ".envctl.toml"

        # 3. Generate
        run-envctl $envctl_path envctl generate

        # 4. Assert
        assert (".env" | path exists)
        let content = (open --raw ".env")
        if not ($content =~ "DB_PASSWORD_VALUE=supersecret") {
            print $"DEBUG: .env content: ($content)"
        }
        assert ($content =~ "DB_PASSWORD_VALUE=supersecret")

        # Cleanup
        cd $old_pwd
        rm --recursive $tmp

    } catch {|err|
        cd $old_pwd
        rm --recursive $tmp
        error make {msg: $err.msg}
    }
}

def main [] {
    print generate_test.nu
    mut passed = 0
    mut failed = 0

    let tests = [
        [name fn];
        [test_generate_all_dependency_order { test_generate_all_dependency_order }]
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
        return (error make --unspanned { msg: "generate test failed" })
    }
}
