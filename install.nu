#!/usr/bin/env nu
# ==============================================================================
# install.nu — Install envctl to a global scripts directory.
#
# Copies envctl.nu + src/ + plugins/ + schemas/ to an install directory,
# then writes a Nushell autoload hook so all envctl commands are available
# in every new session without sourcing anything manually.
#
# — Remote install (nothing downloaded yet):
#     curl -sSL https://raw.githubusercontent.com/arttet/envctl/main/install.nu | nu
#     curl -sSL https://raw.githubusercontent.com/arttet/envctl/main/install.nu | nu - --ref v1.0.0
#
# — Local install (script already downloaded, or running from a cloned repo):
#     nu install.nu                         # install with defaults
#     nu install.nu --prefix ~/.envctl      # custom install directory
#     nu install.nu --no-autoload           # copy files only, skip hook
#     nu install.nu --uninstall             # remove files + autoload hook
#     nu install.nu --dry-run               # show what would be done
#
# When the payload files (envctl.nu, src/, …) are not found next to the script,
# the installer automatically downloads the release archive from GitHub.
#
# Default install directory:
#   Linux / macOS  →  ~/.local/share/envctl
#   Windows        →  %LOCALAPPDATA%\envctl
# ==============================================================================

# Files and directories copied from the repository
const PAYLOAD = [envctl.nu src plugins schemas]

# Autoload hook filename written into $nu.vendor-autoload-dirs
const AUTOLOAD_FILE = "envctl_loader.nu"

# GitHub repository used for remote installs (owner/repo)
const GITHUB_REPO = "arttet/envctl"

# Install or uninstall envctl globally.
@example "Remote install (pipe from curl)"  { main }
@example "Install to custom prefix"         { main --prefix "~/.envctl" }
@example "Install, skip autoload hook"      { main --no-autoload }
@example "Dry run — show plan"              { main --dry-run }
@example "Install specific tag from GitHub" { main --ref v1.0.0 }
@example "Uninstall"                        { main --uninstall }
def main [
    --prefix:    string         # Install directory (default: ~/.local/share/envctl or %LOCALAPPDATA%\envctl)
    --ref:       string = "main" # GitHub branch or tag to download (remote installs only)
    --no-autoload               # Copy files only — do not install the Nushell autoload hook
    --uninstall                 # Remove installed files and the autoload hook
    --dry-run                   # Show what would happen without making any changes
]: nothing -> nothing {
    let install_dir = (resolve-install-dir $prefix)

    if $uninstall {
        do-uninstall $install_dir $dry_run
        return
    }

    # Determine source: local repo if envctl.nu exists next to this script,
    # otherwise fall back to downloading from GitHub.
    let script_dir = ($env | get --optional CURRENT_FILE | path dirname)
    let has_local  = (not ($script_dir | is-empty)) and ($script_dir | path join "envctl.nu" | path exists)

    if $has_local {
        do-install $script_dir $install_dir $no_autoload $dry_run
    } else {
        github-install $ref $install_dir $no_autoload $dry_run
    }
}

def do-install [
    repo_root:   string
    install_dir: string
    no_autoload: bool
    dry_run:     bool
]: nothing -> nothing {

    print $"envctl installer\n  source : ($repo_root)\n  target : ($install_dir)"

    if $dry_run {
        print "  mode   : dry-run\n"
    } else {
        print ""
    }

    for item in $PAYLOAD {
        let src  = ($repo_root  | path join $item)
        let dest = ($install_dir | path join $item)

        if not ($src | path exists) {
            print $"  [skip] ($item) — not found in repo"
            continue
        }

        if $dry_run {
            print $"  [dry] would copy: ($item) → ($dest)"
            continue
        }

        # Ensure parent exists
        let parent = ($dest | path dirname)
        if not ($parent | path exists) { mkdir $parent }

        # Remove stale destination before copy
        if ($dest | path exists) { rm --recursive $dest }

        cp --recursive $src $dest
        print $"  [ok] ($item)"
    }

    if $dry_run {
        print ""
        if not $no_autoload {
            let hook_path = (autoload-path)
            print $"  [dry] would write autoload hook: ($hook_path)"
        }
        print "\nDry run complete — no files written."
        return
    }

    if not $no_autoload {
        install-autoload-hook $install_dir
    }

    print ""
    print $"envctl installed to: ($install_dir)"

    if not $no_autoload {
        print $"autoload hook:       (autoload-path)"
        print ""
        print "Restart your Nushell session or run:"
        print $"  source '(autoload-path)'"
    } else {
        print ""
        print "To load envctl manually, add to your config.nu:"
        print $"  source '($install_dir | path join envctl.nu)'"
    }
}

def do-uninstall [install_dir: path, dry_run: bool]: nothing -> nothing {
    print "envctl uninstaller"
    print $"  target: ($install_dir)"
    if $dry_run { print "  mode  : dry-run\n" } else { print "" }

    # Remove autoload hook
    let hook = (autoload-path)
    if ($hook | path exists) {
        if $dry_run {
            print $"  [dry] would remove autoload hook: ($hook)"
        } else {
            rm --force $hook
            print $"  [ok] removed autoload hook"
        }
    } else {
        print "  [skip] autoload hook not found"
    }

    # Remove install directory
    if ($install_dir | path exists) {
        if $dry_run {
            print $"  [dry] would remove: ($install_dir)"
        } else {
            rm --recursive $install_dir
            print $"  [ok] removed ($install_dir)"
        }
    } else {
        print $"  [skip] install directory not found: ($install_dir)"
    }

    if not $dry_run {
        print "\nenvctl uninstalled."
    }
}

def install-autoload-hook [install_dir: string]: nothing -> nothing {
    let hook_path    = (autoload-path)
    let hook_parent  = ($hook_path | path dirname)
    let envctl_entry = ($install_dir | path join envctl.nu)

    if not ($hook_parent | path exists) { mkdir $hook_parent }

    $"# envctl autoload hook — generated by install.nu\n$env.ENVCTL_HOME = '($install_dir)'\nsource '($envctl_entry)'\n"
    | save --force $hook_path

    print $"  [ok] autoload hook → ($hook_path)"
}

def autoload-path []: nothing -> string {
    $nu.vendor-autoload-dirs | last | path join $AUTOLOAD_FILE
}

def resolve-install-dir [prefix: any] {
    if ($prefix | is-empty) {
        default-install-dir
    } else {
        $prefix | path expand
    }
}

def default-install-dir []: nothing -> string {
    let os = ($nu.os-info | get --optional name | default unknown)

    match $os {
        "windows" => {
            let base = (
                $env | get --optional LOCALAPPDATA
                | default ($env | get --optional USERPROFILE | default "C:\\Users\\Public" | path join AppData Local)
            )
            $base | path join envctl
        }
        _ => {
            let home = ($env | get --optional HOME | default "~")
            $home | path join .local share envctl
        }
    }
}

def github-install [
    ref:         string
    install_dir: string
    no_autoload: bool
    dry_run:     bool
]: nothing -> nothing {
    let url = $"https://github.com/($GITHUB_REPO)/archive/($ref).zip"

    print $"envctl installer \(GitHub\)\n  ref    : ($ref)\n  source : ($url)\n  target : ($install_dir)"

    if $dry_run {
        print "  mode   : dry-run\n"
        print $"  [dry] would download ($url)"
        print $"  [dry] would install to ($install_dir)"
        print "\nDry run complete — no files written."
        return
    }

    print ""

    let tmp_root    = (os-temp-dir | path join $"envctl-install-(random chars --length 8)")
    let zip_path    = ($tmp_root | path join "envctl.zip")
    let extract_dir = ($tmp_root | path join "src")

    mkdir $extract_dir

    print "  Downloading..."
    http get --raw $url | save --force $zip_path

    print "  Extracting..."
    os-extract-zip $zip_path $extract_dir

    let source_root = ($extract_dir | path join $"envctl-($ref)")
    do-install $source_root $install_dir $no_autoload false

    rm --recursive --force $tmp_root
}

def os-temp-dir []: nothing -> string {
    let os = ($nu.os-info | get --optional name | default unknown)
    if $os == "windows" {
        $env | get --optional TEMP | default ($env | get --optional TMP | default "C:\\Windows\\Temp")
    } else {
        $env | get --optional TMPDIR | default "/tmp"
    }
}

def os-extract-zip [zip_path: string, dest_dir: string]: nothing -> nothing {
    let os = ($nu.os-info | get --optional name | default unknown)
    if $os == "windows" {
        powershell -c $"Expand-Archive -LiteralPath '($zip_path)' -DestinationPath '($dest_dir)' -Force"
    } else {
        unzip -q $zip_path -d $dest_dir
    }
}
