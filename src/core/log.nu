# ==============================================================================
# log.nu — Structured aligned logger (fill-based)
# ==============================================================================

const LEVEL_WIDTH = 12
const ns_WIDTH = 12

export def set-quiet [value: bool] {
    $env.LOG_QUIET = $value
}

def is-quiet [] {
    $env | get --optional LOG_QUIET | default false
}

def format-level [level: string, color: string] {
    let padded = ($"[($level)]" | fill --alignment l --character ' ' --width $LEVEL_WIDTH)
    $"(ansi ($color))($padded)(ansi reset)"
}

def format-ns [ns: string] {
    if ($ns | is-empty) {
        "" | fill --alignment l --character ' ' --width $ns_WIDTH
    } else {
        let padded = ($"[($ns)]" | fill --alignment l --character ' ' --width $ns_WIDTH)
        $"(ansi dark_gray)($padded)(ansi reset)"
    }
}

def emit [
    level: string
    color: string
    msg: string
    --ns: string = ""
    --force
] {
    if (not (is-quiet)) or $force {
        let lvl = (format-level $level $color)
        let mod = (format-ns $ns)
        print $"($lvl) ($mod) ($msg)"
    }
}

export def error [msg: string, --ns: string = ""] {
    emit ERROR red_bold $msg --ns $ns --force
}

export def missing [msg: string, --ns: string = ""] {
    emit MISSING red_bold $msg --ns $ns --force
}

export def warn [msg: string, --ns: string = ""] {
    emit WARN yellow_bold $msg --ns $ns
}

export def info [msg: string, --ns: string = ""] {
    emit INFO green_bold $msg --ns $ns
}

export def success [msg: string, --ns: string = ""] {
    emit SUCCESS green_bold $msg --ns $ns
}

export def detail [msg: string, --ns: string = ""] {
    emit DETAILED dark_gray $msg --ns $ns
}
