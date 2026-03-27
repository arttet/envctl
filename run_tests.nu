#!/usr/bin/env nu
# ==============================================================================
# run_tests.nu — envctl test runner
#
# Usage:
#   nu run_tests.nu                                    # all tests
#   nu run_tests.nu --unit                             # unit tests only
#   nu run_tests.nu --file tests/unit/grammar_test.nu  # single file
# ==============================================================================

const TEST_TIMEOUT_MS = 10000

def run-with-timeout [f: string] {
    let job_id = (job spawn { nu $f | complete | job send 0 })
    let start  = (date now)
    loop {
        let elapsed_ms = (((date now) - $start) / 1ms | math floor)
        if $elapsed_ms >= $TEST_TIMEOUT_MS {
            (try { job kill $job_id } catch {})
            return {
                exit_code: 124
                stdout:    ""
                stderr:    $"TIMEOUT: test file exceeded ($TEST_TIMEOUT_MS / 1000)s"
            }
        }
        let msg = (try { job recv --timeout 0sec } catch { null })
        if $msg != null {
            return $msg
        }
        sleep 50ms
    }
}

def main [
    --unit           # Run unit tests only
    --file: string   # Run a specific test file
]: nothing -> nothing {
    let files = if ($file | is-not-empty) {
        if not ($file | path exists) {
            print $"Error: file not found: ($file)"
            exit 1
        }
        [$file]
    } else if $unit {
        (glob "tests/unit/**/*_test.nu")
    } else {
        (
            (glob "tests/unit/**/*_test.nu")
            | append (glob "tests/integration/**/*_test.nu")
        )
    }

    if ($files | is-empty) {
        print "No test files found"
        return
    }

    mut passed = 0
    mut failed = 0
    mut errors = []

    print $"Running ($files | length) test file\(s\)...\n"

    for f in $files {
        print $"── ($f)"
        let result = (run-with-timeout $f)

        if $result.exit_code == 0 {
            $passed += 1
            if ($result.stdout | str trim | is-not-empty) {
                print $result.stdout
            }
        } else if $result.exit_code == 124 {
            $failed += 1
            $errors ++= [$f]
            print $"TIMEOUT \(exceeded ($TEST_TIMEOUT_MS / 1000)s\)"
        } else {
            $failed += 1
            $errors ++= [$f]
            print $"FAILED (exit ($result.exit_code))"
            if ($result.stderr | str trim | is-not-empty) {
                print $result.stderr
            }
            if ($result.stdout | str trim | is-not-empty) {
                print $result.stdout
            }
        }
        print ""
    }

    print $"($passed) passed, ($failed) failed"

    if $failed > 0 {
        print $"\nFailed files:"
        for e in $errors {
            print $"  ($e)"
        }
        exit 1
    }
}
