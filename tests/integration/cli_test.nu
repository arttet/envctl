#!/usr/bin/env nu
# ==============================================================================
# tests/integration/cli_test.nu — Integration tests for basic CLI commands
# ==============================================================================

use std assert

def run-envctl [envctl_path: string, ...args: string]: any -> string {
    nu $envctl_path ...$args
}

def test_init [] {
    let old_pwd = $env.PWD
    let envctl_path = ($env.PWD | path join envctl.nu)
    let tmp = (mktemp --directory)

    try {
        cd $tmp

        # Run init
        run-envctl $envctl_path envctl init

        # Verify files created
        assert (".envctl.toml" | path exists)
        assert (".env.example" | path exists)
        assert (".envctl.lock" | path exists)
        assert (".gitignore" | path exists)

        let gitignore = (open --raw ".gitignore")
        assert ($gitignore | str contains .env)
        assert ($gitignore | str contains .envctl/)

        cd $old_pwd
        rm --recursive $tmp
    } catch {|err|
        cd $old_pwd
        rm --recursive $tmp
        error make {msg: $err.msg}
    }
}

def test_health [] {
    let old_pwd = $env.PWD
    let envctl_path = ($env.PWD | path join envctl.nu)
    let tmp = (mktemp --directory)

    try {
        cd $tmp
        run-envctl $envctl_path envctl init

        # Run health - should pass on fresh init
        let res = (run-envctl $envctl_path envctl health | complete)
        if $res.exit_code != 0 {
            print $"DEBUG: health failed with exit ($res.exit_code)
STDOUT: ($res.stdout)
STDERR: ($res.stderr)"
        }
        assert equal $res.exit_code 0

        cd $old_pwd
        rm --recursive $tmp
    } catch {|err|
        cd $old_pwd
        rm --recursive $tmp
        error make {msg: $err.msg}
    }
}

def main [] {
    print cli_test.nu
    mut passed = 0
    mut failed = 0

    let tests = [
        [name fn];
        [test_init   { test_init }]
        [test_health { test_health }]
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
        return (error make --unspanned { msg: "cli test failed" })
    }
}
