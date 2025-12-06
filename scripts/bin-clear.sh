#!/usr/bin/env bash
set -euo pipefail

#######################################
# Load forge config
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/forge.sh" ]]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/forge.sh"
elif [[ -f "$HOME/mac-forge/forge.sh" ]]; then
    # shellcheck disable=SC1091
    source "$HOME/mac-forge/forge.sh"
fi

#######################################
# Helpers
#######################################
die() {
    echo "✖ $*" >&2
    exit 1
}

usage() {
    cat <<'USAGE'
Usage: bin-clear.sh [target_dir]
  No args    : Clean from current directory.
  target_dir : Clean under the specified directory.
USAGE
    exit 1
}

safe_target_or_exit() {
    local path="$1"

    case "$path" in
        /|/bin|/sbin|/usr|/System|/Library)
            die "Refusing to operate on unsafe path: $path"
            ;;
    esac
}

#######################################
# Main
#######################################
main() {
    local target dirs=()

    if (( $# > 1 )); then
        usage
    fi

    if (( $# == 1 )); then
        target="$1"
    else
        target="$(pwd)"
    fi

    [[ -d "$target" ]] || die "Target directory does not exist: $target"
    target="$(cd "$target" && pwd)"
    safe_target_or_exit "$target"

    echo "Scanning for bin/debug directories under: $target"

    while IFS= read -r -d '' dir; do
        dirs+=("$dir")
    done < <(find "$target" -type d \( -iname bin -o -iname debug \) -print0)

    if (( ${#dirs[@]} == 0 )); then
        echo "No bin or debug directories found."
        return 0
    fi

    for dir in "${dirs[@]}"; do
        echo "Removing: $dir"
        rm -rf "$dir"
    done

    echo "Removed ${#dirs[@]} directorie(s)."
}

main "$@"
