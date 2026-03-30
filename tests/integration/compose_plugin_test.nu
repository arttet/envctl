#!/usr/bin/env nu
# ==============================================================================
# tests/integration/compose_plugin_test.nu — Integration tests for the compose
# provider plugin (plugins/providers/compose.nu).
#
# Tests exercise the plugin functions directly against real filesystem fixtures
# and one end-to-end test that runs the full envfile generate pipeline.
#
# Run directly:  nu tests/integration/compose_plugin_test.nu
# Via runner:    nu run_tests.nu --file tests/integration/compose_plugin_test.nu
# ==============================================================================

use std assert

use ../../plugins/providers/compose.nu [
    manifest
    collect-files
    path-separator
    default-services
]

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Build a minimal ctx record suitable for calling compose functions.
def make-ctx [
    base_dir: string
    --stage: string = "dev"
    --services: record = {}
    --base-files: list<string> = ["compose.yml"]
    --envctl-services: string = ""
    --envctl-variants: string = ""
    --git-root: string = ""
]: nothing -> record {
    {
        stage: $stage
        cfg: {
            providers: {
                compose: {
                    base_dir:   $base_dir
                    base_files: $base_files
                    services:   $services
                }
            }
        }
        cli: {
            ENVCTL_SERVICES: $envctl_services
            ENVCTL_VARIANTS: $envctl_variants
        }
        env_vars: {
            GIT_ROOT_DIR: (if ($git_root | is-empty) { $base_dir } else { $git_root })
        }
        providers:    {}
        secrets_root: "."
    }
}

def with-tmp-dir [body: closure] {
    let tmp = (mktemp --directory)
    try {
        do $body $tmp
        rm --recursive --force $tmp
    } catch {|err|
        rm --recursive --force $tmp
        error make {msg: $err.msg}
    }
}

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

# ---------------------------------------------------------------------------
# Manifest contract
# ---------------------------------------------------------------------------

def test_manifest_name [] {
    assert equal (manifest).name "compose"
}

def test_manifest_version [] {
    assert equal (manifest).version "1.0.0"
}

def test_manifest_kind [] {
    assert equal (manifest).kind "provider"
}

def test_manifest_provides_collect_files [] {
    assert ("collect-files" in (manifest).provides)
}

def test_manifest_provides_path_separator [] {
    assert ("path-separator" in (manifest).provides)
}

def test_manifest_config_schema [] {
    assert equal (manifest).config_schema "compose.config.schema.toml"
}

def test_manifest_health_schema [] {
    assert equal (manifest).health_schema "compose.health.schema.toml"
}

def test_manifest_resolve_has_collect_files [] {
    assert ((manifest).resolve | columns | any { $in == "collect-files" })
}

def test_manifest_resolve_has_path_separator [] {
    assert ((manifest).resolve | columns | any { $in == "path-separator" })
}

def test_manifest_requires_git_root_dir [] {
    assert ("GIT_ROOT_DIR" in (manifest).requires)
}

# ---------------------------------------------------------------------------
# path-separator
# ---------------------------------------------------------------------------

def test_path_separator_is_os_appropriate [] {
    let sep = (path-separator {})
    let expected = if $nu.os-info.name == "windows" { ";" } else { ":" }
    assert equal $sep $expected
}

# ---------------------------------------------------------------------------
# collect-files — base file only
# ---------------------------------------------------------------------------

def test_collect_files_base_compose_yml_included [] {
    with-tmp-dir {|tmp|
        ($tmp | path join "compose.yml") | save --force ($tmp | path join "compose.yml")
        "" | save --force ($tmp | path join "compose.yml")

        let ctx = (make-ctx $tmp)
        let result = (collect-files $ctx)

        assert ($result | str contains "compose.yml") $"expected compose.yml in result, got: ($result)"
    }
}

def test_collect_files_missing_base_file_skipped [] {
    with-tmp-dir {|tmp|
        # No compose.yml created — must produce empty result
        let ctx = (make-ctx $tmp)
        let result = (collect-files $ctx)

        assert ($result | is-empty) $"expected empty result when no files exist, got: ($result)"
    }
}

def test_collect_files_custom_base_file [] {
    with-tmp-dir {|tmp|
        "" | save --force ($tmp | path join "docker-compose.yml")

        let ctx = (make-ctx $tmp --base-files ["docker-compose.yml"])
        let result = (collect-files $ctx)

        assert ($result | str contains "docker-compose.yml") $"expected docker-compose.yml in result, got: ($result)"
    }
}

# ---------------------------------------------------------------------------
# collect-files — stage-specific file
# ---------------------------------------------------------------------------

def test_collect_files_stage_file_appended [] {
    with-tmp-dir {|tmp|
        "" | save --force ($tmp | path join "compose.yml")
        "" | save --force ($tmp | path join "compose.dev.yml")

        let ctx = (make-ctx $tmp --stage "dev")
        let result = (collect-files $ctx)

        assert ($result | str contains "compose.yml")     $"expected compose.yml in result"
        assert ($result | str contains "compose.dev.yml") $"expected compose.dev.yml in result"
    }
}

def test_collect_files_stage_file_absent_not_included [] {
    with-tmp-dir {|tmp|
        "" | save --force ($tmp | path join "compose.yml")
        # compose.prod.yml does NOT exist

        let ctx = (make-ctx $tmp --stage "prod")
        let result = (collect-files $ctx)

        assert (not ($result | str contains "compose.prod.yml")) "compose.prod.yml must not appear when it does not exist"
    }
}

def test_collect_files_multiple_base_files_ordered [] {
    with-tmp-dir {|tmp|
        "" | save --force ($tmp | path join "compose.yml")
        "" | save --force ($tmp | path join "compose.override.yml")

        let ctx = (make-ctx $tmp --base-files ["compose.yml" "compose.override.yml"])
        let result = (collect-files $ctx)
        let sep = (path-separator {})
        let parts = ($result | split row $sep)

        assert (($parts | length) == 2) $"expected 2 files in result, got: ($result)"
        assert ($parts.0 | str contains "compose.yml")          "compose.yml must be first"
        assert ($parts.1 | str contains "compose.override.yml") "compose.override.yml must be second"
    }
}

# ---------------------------------------------------------------------------
# collect-files — services
# ---------------------------------------------------------------------------

def test_collect_files_service_compose_file_included [] {
    with-tmp-dir {|tmp|
        "" | save --force ($tmp | path join "compose.yml")
        mkdir ($tmp | path join "mysql")
        "" | save --force ($tmp | path join "mysql" | path join "compose.mysql.yml")

        let ctx = (make-ctx $tmp --services {mysql: {default: true}})
        let result = (collect-files $ctx)

        assert ($result | str contains "compose.mysql.yml") $"expected compose.mysql.yml in result, got: ($result)"
    }
}

def test_collect_files_service_not_default_excluded [] {
    with-tmp-dir {|tmp|
        "" | save --force ($tmp | path join "compose.yml")
        mkdir ($tmp | path join "redis")
        "" | save --force ($tmp | path join "redis" | path join "compose.redis.yml")

        # default = false → service should not be selected automatically
        let ctx = (make-ctx $tmp --services {redis: {default: false}})
        let result = (collect-files $ctx)

        assert (not ($result | str contains "compose.redis.yml")) "non-default service must not be auto-selected"
    }
}

def test_collect_files_service_variant_file_included [] {
    with-tmp-dir {|tmp|
        "" | save --force ($tmp | path join "compose.yml")
        mkdir ($tmp | path join "db")
        "" | save --force ($tmp | path join "db" | path join "compose.db.engine.postgres.yml")

        let ctx = (make-ctx $tmp --services {db: {default: true, engine: "postgres"}})
        let result = (collect-files $ctx)

        assert ($result | str contains "compose.db.engine.postgres.yml") $"expected variant file in result, got: ($result)"
    }
}

def test_collect_files_service_missing_variant_file_skipped [] {
    with-tmp-dir {|tmp|
        "" | save --force ($tmp | path join "compose.yml")
        mkdir ($tmp | path join "db")
        # Variant file does NOT exist

        let ctx = (make-ctx $tmp --services {db: {default: true, engine: "postgres"}})
        let result = (collect-files $ctx)

        assert (not ($result | str contains "compose.db.engine.postgres.yml")) "missing variant file must be skipped"
    }
}

# ---------------------------------------------------------------------------
# collect-files — service-level stage files
# ---------------------------------------------------------------------------

def test_collect_files_service_stage_file_included [] {
    with-tmp-dir {|tmp|
        "" | save --force ($tmp | path join "compose.yml")
        mkdir ($tmp | path join "mysql")
        "" | save --force ($tmp | path join "mysql" | path join "compose.mysql.yml")
        "" | save --force ($tmp | path join "mysql" | path join "compose.mysql.dev.yml")

        let ctx = (make-ctx $tmp --stage "dev" --services {mysql: {default: true}})
        let result = (collect-files $ctx)

        assert ($result | str contains "compose.mysql.yml")     "service base must be included"
        assert ($result | str contains "compose.mysql.dev.yml") "service stage file must be included for --stage dev"
    }
}

def test_collect_files_service_stage_file_after_base [] {
    with-tmp-dir {|tmp|
        "" | save --force ($tmp | path join "compose.yml")
        mkdir ($tmp | path join "mysql")
        "" | save --force ($tmp | path join "mysql" | path join "compose.mysql.yml")
        "" | save --force ($tmp | path join "mysql" | path join "compose.mysql.dev.yml")

        let ctx = (make-ctx $tmp --stage "dev" --services {mysql: {default: true}})
        let result = (collect-files $ctx)
        let sep = (path-separator {})
        let parts = ($result | split row $sep)

        let not_found = -1
        let base_idx  = ($parts | enumerate | where {|e| $e.item | str contains "compose.mysql.yml" } | get --optional 0.index | default $not_found)
        let stage_idx = ($parts | enumerate | where {|e| $e.item | str contains "compose.mysql.dev.yml" } | get --optional 0.index | default $not_found)

        assert ($base_idx != -1)  "compose.mysql.yml must be present"
        assert ($stage_idx != -1) "compose.mysql.dev.yml must be present"
        assert ($base_idx < $stage_idx) $"service base \(pos ($base_idx)\) must come before stage file \(pos ($stage_idx)\)"
    }
}

def test_collect_files_service_stage_file_absent_skipped [] {
    with-tmp-dir {|tmp|
        "" | save --force ($tmp | path join "compose.yml")
        mkdir ($tmp | path join "mysql")
        "" | save --force ($tmp | path join "mysql" | path join "compose.mysql.yml")
        # compose.mysql.prod.yml does NOT exist

        let ctx = (make-ctx $tmp --stage "prod" --services {mysql: {default: true}})
        let result = (collect-files $ctx)

        assert (not ($result | str contains "compose.mysql.prod.yml")) "missing service stage file must be skipped"
    }
}

def test_collect_files_service_stage_different_stages [] {
    with-tmp-dir {|tmp|
        "" | save --force ($tmp | path join "compose.yml")
        mkdir ($tmp | path join "db")
        "" | save --force ($tmp | path join "db" | path join "compose.db.yml")
        "" | save --force ($tmp | path join "db" | path join "compose.db.dev.yml")
        "" | save --force ($tmp | path join "db" | path join "compose.db.prod.yml")

        let ctx_dev  = (make-ctx $tmp --stage "dev"  --services {db: {default: true}})
        let ctx_prod = (make-ctx $tmp --stage "prod" --services {db: {default: true}})

        let result_dev  = (collect-files $ctx_dev)
        let result_prod = (collect-files $ctx_prod)

        assert ($result_dev  | str contains "compose.db.dev.yml")  "dev stage must include compose.db.dev.yml"
        assert ($result_prod | str contains "compose.db.prod.yml") "prod stage must include compose.db.prod.yml"
        assert (not ($result_dev  | str contains "compose.db.prod.yml")) "dev stage must NOT include compose.db.prod.yml"
        assert (not ($result_prod | str contains "compose.db.dev.yml"))  "prod stage must NOT include compose.db.dev.yml"
    }
}

# ---------------------------------------------------------------------------
# collect-files — variant stage files (compose.<svc>.<dep>.<variant>.<stage>.yml)
# ---------------------------------------------------------------------------

def test_collect_files_variant_stage_file_included [] {
    with-tmp-dir {|tmp|
        "" | save --force ($tmp | path join "compose.yml")
        mkdir ($tmp | path join "observability")
        "" | save --force ($tmp | path join "observability" | path join "compose.observability.metrics.prometheus.yml")
        "" | save --force ($tmp | path join "observability" | path join "compose.observability.metrics.prometheus.dev.yml")

        let ctx = (make-ctx $tmp --stage "dev" --services {observability: {default: true, metrics: "prometheus"}})
        let result = (collect-files $ctx)

        assert ($result | str contains "compose.observability.metrics.prometheus.yml")     "variant base must be included"
        assert ($result | str contains "compose.observability.metrics.prometheus.dev.yml") "variant stage file must be included for --stage dev"
    }
}

def test_collect_files_variant_stage_file_absent_skipped [] {
    with-tmp-dir {|tmp|
        "" | save --force ($tmp | path join "compose.yml")
        mkdir ($tmp | path join "observability")
        "" | save --force ($tmp | path join "observability" | path join "compose.observability.metrics.prometheus.yml")
        # compose.observability.metrics.prometheus.prod.yml does NOT exist

        let ctx = (make-ctx $tmp --stage "prod" --services {observability: {default: true, metrics: "prometheus"}})
        let result = (collect-files $ctx)

        assert ($result | str contains "compose.observability.metrics.prometheus.yml") "variant base must be included"
        assert (not ($result | str contains "compose.observability.metrics.prometheus.prod.yml")) "missing variant stage file must be skipped"
    }
}

def test_collect_files_variant_stage_file_after_variant_base [] {
    with-tmp-dir {|tmp|
        "" | save --force ($tmp | path join "compose.yml")
        mkdir ($tmp | path join "observability")
        "" | save --force ($tmp | path join "observability" | path join "compose.observability.metrics.prometheus.yml")
        "" | save --force ($tmp | path join "observability" | path join "compose.observability.metrics.prometheus.dev.yml")

        let ctx = (make-ctx $tmp --stage "dev" --services {observability: {default: true, metrics: "prometheus"}})
        let result = (collect-files $ctx)
        let sep = (path-separator {})
        let parts = ($result | split row $sep)

        let not_found = -1
        let base_idx  = ($parts | enumerate | where {|e| $e.item | str ends-with "compose.observability.metrics.prometheus.yml"  } | get --optional 0.index | default $not_found)
        let stage_idx = ($parts | enumerate | where {|e| $e.item | str ends-with "compose.observability.metrics.prometheus.dev.yml" } | get --optional 0.index | default $not_found)

        assert ($base_idx  != $not_found) "variant base must be present"
        assert ($stage_idx != $not_found) "variant stage file must be present"
        assert ($base_idx < $stage_idx)   $"variant base \(pos ($base_idx)\) must come before variant stage file \(pos ($stage_idx)\)"
    }
}

# ---------------------------------------------------------------------------
# collect-files — ENVCTL_SERVICES CLI override
# ---------------------------------------------------------------------------

def test_collect_files_envctl_services_override [] {
    with-tmp-dir {|tmp|
        "" | save --force ($tmp | path join "compose.yml")
        mkdir ($tmp | path join "redis")
        "" | save --force ($tmp | path join "redis" | path join "compose.redis.yml")
        mkdir ($tmp | path join "mysql")
        "" | save --force ($tmp | path join "mysql" | path join "compose.mysql.yml")

        # redis is not default, but selected via CLI override
        let ctx = (
            make-ctx $tmp
                --services {mysql: {default: true}, redis: {default: false}}
                --envctl-services "redis"
        )
        let result = (collect-files $ctx)

        assert ($result | str contains "compose.redis.yml") "ENVCTL_SERVICES should select redis"
        assert (not ($result | str contains "compose.mysql.yml")) "mysql must not appear when overridden by ENVCTL_SERVICES"
    }
}

def test_collect_files_envctl_services_multiple [] {
    with-tmp-dir {|tmp|
        "" | save --force ($tmp | path join "compose.yml")
        mkdir ($tmp | path join "redis")
        "" | save --force ($tmp | path join "redis" | path join "compose.redis.yml")
        mkdir ($tmp | path join "mysql")
        "" | save --force ($tmp | path join "mysql" | path join "compose.mysql.yml")

        let ctx = (
            make-ctx $tmp
                --services {mysql: {default: false}, redis: {default: false}}
                --envctl-services "mysql,redis"
        )
        let result = (collect-files $ctx)

        assert ($result | str contains "compose.mysql.yml") "mysql should appear with CSV override"
        assert ($result | str contains "compose.redis.yml") "redis should appear with CSV override"
    }
}

# ---------------------------------------------------------------------------
# default-services helper
# ---------------------------------------------------------------------------

def test_default_services_returns_default_true_only [] {
    with-tmp-dir {|tmp|
        let ctx = (make-ctx $tmp --services {mysql: {default: true}, redis: {default: false}})
        let result = (default-services $ctx)

        assert ("mysql" in $result) "mysql (default=true) must be in default-services"
        assert (not ("redis" in $result)) "redis (default=false) must not be in default-services"
    }
}

def test_default_services_empty_when_no_defaults [] {
    with-tmp-dir {|tmp|
        let ctx = (make-ctx $tmp --services {redis: {default: false}})
        let result = (default-services $ctx)

        assert ($result | is-empty) "no default=true services → result must be empty"
    }
}

# ---------------------------------------------------------------------------
# Full pipeline — {{ provider:compose.collect-files }} resolves in envfile generate
# ---------------------------------------------------------------------------

def test_collect_files_resolves_in_envfile_generate [] {
    with-tmp-project {|envctl_path|
        # Create compose files
        "" | save --force "compose.yml"
        "" | save --force "compose.dev.yml"

        let cwd = $env.PWD
        let toml_cwd = ($cwd | str replace --all '\' '\\')

        # Write .envctl.toml with compose provider configured
        (
            "schema = \"v1\"\n\n"
            + "[envfile]\nfile = \".env\"\npattern = \".env.example\"\n\n"
            + "[secrets]\nbase_dir = \".\"\n\n"
            + "[providers]\nenabled = [\"compose\"]\n\n"
            + $"[providers.compose]\nbase_dir = \"($toml_cwd)\"\nbase_files = [\"compose.yml\"]\n"
        ) | save ".envctl.toml"

        "COMPOSE_FILE={{ provider:compose.collect-files }}" | save ".env.example"

        nu $envctl_path envctl envfile generate

        let content = (open --raw ".env")
        assert (not ($content | str contains "{{")) $"unresolved token in .env: ($content)"
        assert ($content | str contains "compose.yml") $"expected compose.yml in COMPOSE_FILE, got: ($content)"
    }
}

def test_collect_files_stage_file_resolves_in_envfile_generate [] {
    with-tmp-project {|envctl_path|
        "" | save --force "compose.yml"
        "" | save --force "compose.dev.yml"

        let cwd = $env.PWD
        let toml_cwd = ($cwd | str replace --all '\' '\\')

        (
            "schema = \"v1\"\n\n"
            + "[envfile]\nfile = \".env\"\npattern = \".env.example\"\n\n"
            + "[secrets]\nbase_dir = \".\"\n\n"
            + "[providers]\nenabled = [\"compose\"]\n\n"
            + $"[providers.compose]\nbase_dir = \"($toml_cwd)\"\nbase_files = [\"compose.yml\"]\n"
        ) | save ".envctl.toml"

        "COMPOSE_FILE={{ provider:compose.collect-files }}" | save ".env.example"

        with-env { ENVCTL_STAGE: "dev" } { nu $envctl_path envctl envfile generate }

        let content = (open --raw ".env")
        assert ($content | str contains "compose.dev.yml") $"expected compose.dev.yml for stage=dev, got: ($content)"
    }
}

def test_path_separator_resolves_in_envfile_generate [] {
    with-tmp-project {|envctl_path|
        let cwd = $env.PWD
        let toml_cwd = ($cwd | str replace --all '\' '\\')

        (
            "schema = \"v1\"\n\n"
            + "[envfile]\nfile = \".env\"\npattern = \".env.example\"\n\n"
            + "[secrets]\nbase_dir = \".\"\n\n"
            + "[providers]\nenabled = [\"compose\"]\n\n"
            + $"[providers.compose]\nbase_dir = \"($toml_cwd)\"\nbase_files = [\"compose.yml\"]\n"
        ) | save ".envctl.toml"

        "COMPOSE_PATH_SEPARATOR={{ provider:compose.path-separator }}" | save ".env.example"

        nu $envctl_path envctl envfile generate

        let content = (open --raw ".env")
        let expected_sep = if $nu.os-info.name == "windows" { ";" } else { ":" }
        assert (not ($content | str contains "{{")) $"unresolved token in .env: ($content)"
        assert ($content | str contains $expected_sep) $"expected separator ($expected_sep) in .env, got: ($content)"
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main [] {
    print "compose_plugin_test.nu"
    mut passed = 0
    mut failed = 0

    let tests = [
        [name fn];
        [test_manifest_name                              { test_manifest_name }]
        [test_manifest_version                           { test_manifest_version }]
        [test_manifest_kind                              { test_manifest_kind }]
        [test_manifest_provides_collect_files            { test_manifest_provides_collect_files }]
        [test_manifest_provides_path_separator           { test_manifest_provides_path_separator }]
        [test_manifest_config_schema                     { test_manifest_config_schema }]
        [test_manifest_health_schema                     { test_manifest_health_schema }]
        [test_manifest_resolve_has_collect_files         { test_manifest_resolve_has_collect_files }]
        [test_manifest_resolve_has_path_separator        { test_manifest_resolve_has_path_separator }]
        [test_manifest_requires_git_root_dir             { test_manifest_requires_git_root_dir }]
        [test_path_separator_is_os_appropriate           { test_path_separator_is_os_appropriate }]
        [test_collect_files_base_compose_yml_included    { test_collect_files_base_compose_yml_included }]
        [test_collect_files_missing_base_file_skipped    { test_collect_files_missing_base_file_skipped }]
        [test_collect_files_custom_base_file             { test_collect_files_custom_base_file }]
        [test_collect_files_stage_file_appended          { test_collect_files_stage_file_appended }]
        [test_collect_files_stage_file_absent_not_included { test_collect_files_stage_file_absent_not_included }]
        [test_collect_files_multiple_base_files_ordered  { test_collect_files_multiple_base_files_ordered }]
        [test_collect_files_service_compose_file_included { test_collect_files_service_compose_file_included }]
        [test_collect_files_service_not_default_excluded  { test_collect_files_service_not_default_excluded }]
        [test_collect_files_service_variant_file_included { test_collect_files_service_variant_file_included }]
        [test_collect_files_service_missing_variant_file_skipped { test_collect_files_service_missing_variant_file_skipped }]
        [test_collect_files_service_stage_file_included          { test_collect_files_service_stage_file_included }]
        [test_collect_files_service_stage_file_after_base        { test_collect_files_service_stage_file_after_base }]
        [test_collect_files_service_stage_file_absent_skipped    { test_collect_files_service_stage_file_absent_skipped }]
        [test_collect_files_service_stage_different_stages       { test_collect_files_service_stage_different_stages }]
        [test_collect_files_variant_stage_file_included          { test_collect_files_variant_stage_file_included }]
        [test_collect_files_variant_stage_file_absent_skipped    { test_collect_files_variant_stage_file_absent_skipped }]
        [test_collect_files_variant_stage_file_after_variant_base { test_collect_files_variant_stage_file_after_variant_base }]
        [test_collect_files_envctl_services_override     { test_collect_files_envctl_services_override }]
        [test_collect_files_envctl_services_multiple     { test_collect_files_envctl_services_multiple }]
        [test_default_services_returns_default_true_only { test_default_services_returns_default_true_only }]
        [test_default_services_empty_when_no_defaults    { test_default_services_empty_when_no_defaults }]
        [test_collect_files_resolves_in_envfile_generate { test_collect_files_resolves_in_envfile_generate }]
        [test_collect_files_stage_file_resolves_in_envfile_generate { test_collect_files_stage_file_resolves_in_envfile_generate }]
        [test_path_separator_resolves_in_envfile_generate { test_path_separator_resolves_in_envfile_generate }]
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
        return (error make --unspanned { msg: "compose plugin test failed" })
    }
}
