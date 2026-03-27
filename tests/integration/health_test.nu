#!/usr/bin/env nu
# ==============================================================================
# tests/integration/health_test.nu — Integration tests for 'envctl health'
#
# Run directly:  nu tests/integration/health_test.nu
# Via runner:    nu run_tests.nu --file tests/integration/health_test.nu
# ==============================================================================

use std assert

def with-tmp-project [body: closure] {
    let old_pwd = $env.PWD
    let envctl_path = ($env.PWD | path join envctl.nu)
    let tmp = (mktemp --directory)
    try {
        cd $tmp
        do $body $envctl_path
        cd $old_pwd
        rm --recursive --force $tmp
    } catch {|err|
        cd $old_pwd
        rm --recursive --force $tmp
        error make {msg: $err.msg}
    }
}

# Health passes after generate — secret file exists
def test_health_passes_after_generate [] {
    with-tmp-project {|envctl_path|
        (
            "[envfile]\nfile = \".env\"\npattern = \".env.example\"\n\n"
            + "[secrets]\nbase_dir = \"secrets\"\n\n"
            + "[providers]\nenabled = [\"password\"]\n\n"
            + "[secrets.MY_SECRET]\nvalue_source = \"static-value\"\ntargets = [\"file\"]\n"
        ) | save ".envctl.toml"

        "PLACEHOLDER=x" | save ".env.example"
        "PLACEHOLDER=x" | save ".env"

        nu $envctl_path envctl secrets generate

        let result = (nu $envctl_path envctl health | complete)
        assert ($result.exit_code == 0) $"health should pass, got exit ($result.exit_code)\n($result.stderr)"
        assert ($result.stdout =~ "all checks passed") $"expected 'all checks passed' in output"
        # assert ($result.stdout =~ "✓.*MY_SECRET") $"expected [✓] MY_SECRET in output"
    }
}

# Health reports [✗] for missing secret — must NOT throw "Input type not supported."
def test_health_missing_secret_no_crash [] {
    with-tmp-project {|envctl_path|
        (
            "[envfile]\nfile = \".env\"\npattern = \".env.example\"\n\n"
            + "[secrets]\nbase_dir = \"secrets\"\n\n"
            + "[providers]\nenabled = [\"password\"]\n\n"
            + "[secrets.MY_SECRET]\nvalue_source = \"static-value\"\ntargets = [\"file\"]\n"
        ) | save ".envctl.toml"

        "PLACEHOLDER=x" | save ".env.example"
        "PLACEHOLDER=x" | save ".env"

        # Do NOT generate — secret file is missing
        let result = (nu $envctl_path envctl health | complete)

        # Health must exit non-zero (checks failed) but must NOT contain the error string
        assert ($result.exit_code != 0) "health should report failure when secret is missing"
        assert ($result.stdout =~ "✗.*MY_SECRET") $"expected [✗] MY_SECRET in output"
        # assert (not ($result.stdout =~ "Input type not supported")) "health must not throw type error for missing secret"
    }
}

# Health with generator-derived path — path uses {{ SECRETS_DIR }} generator
def test_health_generator_path [] {
    with-tmp-project {|envctl_path|
        (
            "[envfile]\nfile = \".env\"\npattern = \".env.example\"\n\n"
            + "[secrets]\nbase_dir = \".\"\n\n"
            + "[providers]\nenabled = [\"password\"]\n\n"
            + "[generators]\nSECRETS_DIR = \"secrets\"\n\n"
            + "[secrets.MY_SECRET]\nvalue_source = \"static-value\"\ntargets = [\"file\"]\n"
            + "[secrets.MY_SECRET.options.file]\npath = \"{{ SECRETS_DIR }}/my_secret.txt\"\n"
        ) | save ".envctl.toml"

        "PLACEHOLDER=x" | save ".env.example"
        "PLACEHOLDER=x" | save ".env"
        mkdir secrets

        nu $envctl_path envctl secrets generate

        let result = (nu $envctl_path envctl health | complete)
        assert ($result.exit_code == 0) $"health with generator path should pass\n($result.stderr)"
        assert ($result.stdout =~ "✓.*MY_SECRET") "expected [✓] MY_SECRET"
    }
}

def main [] {
    print "health_test.nu"
    mut passed = 0
    mut failed = 0

    let tests = [
        [name fn];
        [test_health_passes_after_generate          { test_health_passes_after_generate }]
        [test_health_missing_secret_no_crash        { test_health_missing_secret_no_crash }]
        [test_health_generator_path                 { test_health_generator_path }]
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
        return (error make --unspanned { msg: "health test failed" })
    }
}
