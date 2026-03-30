#!/usr/bin/env nu

use ./src/core/log.nu
use ./src/core/constants.nu [DEFAULT_CONFIG_PATH DEFAULT_STAGE ENVCTL_VERSION]

export use ./src/commands/init.nu [
    "envctl init"
]

export use ./src/commands/generate.nu [
    "envctl generate"
]

export use ./src/commands/health.nu [
    "envctl health"
]

export use ./src/commands/plugins.nu [
    "envctl plugins list"
]

export use ./src/commands/envfile.nu [
    "envctl envfile generate"
    "envctl envfile diff"
]

export use ./src/commands/secrets.nu [
    "envctl secrets generate"
    "envctl secrets rotate"
    "envctl secrets rotate-all"
]

export use ./src/commands/certs.nu [
    "envctl certs status"
    "envctl certs generate"
    "envctl certs rotate"
    "envctl certs rotate-all"
]

export-env {
    load-env {
        ENVCTL_HOME: ($env | get --optional ENVCTL_HOME | default ($env.CURRENT_FILE | path expand | path dirname))
        ENVCTL_CONFIG: ($env.ENVCTL_CONFIG?  | default $DEFAULT_CONFIG_PATH)
        ENVCTL_STAGE: ($env.ENVCTL_STAGE?   | default $DEFAULT_STAGE)
        ENVCTL_DRY_RUN: ($env.ENVCTL_DRY_RUN? | default "false")
        ENVCTL_QUIET: ($env.ENVCTL_QUIET?   | default "false")
    }
}

export def "envctl version" []: nothing -> string {
    $ENVCTL_VERSION
}

export def envctl []: nothing -> nothing {
    let subcommands = (help commands | where name =~ "^envctl " | get name)
    print $"(ansi green)Usage(ansi reset): envctl (char lparen)($subcommands | str join '|')(char rparen)"
    print "enjoy envctl!"
}

def main [...args: string]: nothing -> nothing {
    if ($args | is-empty) {
        envctl
        return
    }

    let script_path = ($env.CURRENT_FILE | path expand)
    let cmd = ($args | str join " ")
    nu -c $"source '($script_path)'; ($cmd)"
}
