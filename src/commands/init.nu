# ==============================================================================
# commands/init.nu — Initialize a new envctl project in the current directory.
# ==============================================================================

use ../core/log.nu
use ../core/constants.nu [
    DEFAULT_CONFIG_PATH
    DEFAULT_LOCK_PATH
    DEFAULT_ENVFILE
    DEFAULT_PATTERN
]

# Initialize a new envctl project in the current directory.
#
# What it does:
#   1. Creates .envctl.toml from .envctl.example.toml if it exists,
#      otherwise writes a minimal working config.
#   2. Creates .env.example if it does not exist.
#   3. Creates an empty .envctl.lock to anchor future version checks.
#   4. Appends envctl-generated files to .gitignore if not already present.
#
# Safe to re-run: existing files are never overwritten.
@example "Initialize project with defaults"   { envctl init }
@example "Initialize with custom config path" { envctl init --config .envctl.prod.toml }
export def "envctl init" [
    --config: string   # Config file to create (default: .envctl.toml)
]: nothing -> nothing {
    let config_path = ($config | default $DEFAULT_CONFIG_PATH)

    # config
    if ($config_path | path exists) {
        log warn --ns init $"($config_path) already exists — skipping"
    } else {
        let example = ".envctl.example.toml"
        if ($example | path exists) {
            cp $example $config_path
            log success --ns init $"created ($config_path) from ($example)"
        } else {
            # Minimal config — enough to run envfile generate + secrets generate
            (
                "schema = \"v1\"\n\n"
                + "[envfile]\n"
                + "file    = \".env\"\n"
                + "pattern = \".env.example\"\n"
                + "excluded = []\n\n"
                + "[secrets]\n"
                + "base_dir = \".\"\n\n"
                + "[providers]\n"
                + "enabled = [\"git\", \"password\", \"compose\", \"certs\"]\n\n"
                + "[generators]\n"
                + "GIT_ROOT_DIR = \"{{ provider:git.top-level-dir }}\"\n"
            ) | save $config_path

            log success --ns init $"created minimal ($config_path)"
        }
    }

    # .env.example
    if ($DEFAULT_PATTERN | path exists) {
        log warn --ns init $"($DEFAULT_PATTERN) already exists — skipping"
    } else {
        (
            "# .env.example — committed to git, never contains real secrets.\n"
            + "# Run: envctl generate\n\n"
            + "# Example — replace with your actual variables:\n"
            + "# APP_ENV=development\n"
            + "# DB_HOST=localhost\n"
            + "# DB_PORT=5432\n"
        ) | save $DEFAULT_PATTERN

        log success --ns init $"created ($DEFAULT_PATTERN)"
    }

    # lock
    if ($DEFAULT_LOCK_PATH | path exists) {
        log warn --ns init $"($DEFAULT_LOCK_PATH) already exists — skipping"
    } else {
        "[providers]\n[backends]\n" | save $DEFAULT_LOCK_PATH

        log success --ns init $"created ($DEFAULT_LOCK_PATH)"
    }

    # .gitignore
    let ignore_entries = [$DEFAULT_ENVFILE .envctl/]
    let gitignore = ".gitignore"

    let existing_lines = if ($gitignore | path exists) {
        open --raw $gitignore | lines
    } else {
        []
    }

    let missing = ($ignore_entries | where not ($existing_lines | any {|line| ($line | str trim) == $it }))
    if ($missing | is-not-empty) {
        let block = ($missing | str join "\n")
        let sep   = if ($existing_lines | is-empty) { "" } else { "\n" }
        $"($sep)# envctl generated\n($block)\n" | save --append $gitignore

        log success --ns init $"added to .gitignore: ($missing | str join ', ')"
    } else {
        log detail --ns init ".gitignore already up-to-date"
    }

    log success --ns init "done — next: envctl generate"
}
