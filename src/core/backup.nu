# ==============================================================================
# backup.nu — Timestamped file backup before overwrite.
#
# By default backs up next to the original: <file>.bak_<timestamp>
# Pass --dir to redirect to a specific directory (e.g. .envctl/ for .env).
# ==============================================================================
# Create a timestamped backup of a file before overwriting.
# Returns backup path if file existed, null if file does not exist.

@example "Backup next to original"   { backup-file "data/secrets/db.key" }
@example "Backup to custom dir"      { backup-file ".env" --dir ".envctl" }
@example "Backup missing — null"     { backup-file ".env.missing" }
export def backup-file [
    file: string   # Path to the file to back up
    --dir: string  # Write backup here instead of next to the original
]: nothing -> string {
    if not ($file | path exists) {
        return null
    }

    let timestamp = (date now | format date "%Y%m%d_%H%M%S")
    let backup_path = if ($dir | default "" | is-empty) { $"($file).bak_($timestamp)" } else {
        mkdir $dir
        $"($dir)/($file | path basename).bak_($timestamp)"
    }

    cp $file $backup_path

    $backup_path
}
