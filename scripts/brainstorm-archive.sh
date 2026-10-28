#!/usr/bin/env bash
set -euo pipefail

die() {
    echo "✖ $*" >&2
    exit 1
}

# Exit code 3 means "nothing to archive" (used by --all to skip quietly).
EXIT_NOTHING=3

if [[ "${1:-}" == "--all" ]]; then
    [[ $# -eq 1 ]] || die "Usage: brainstorm-archive [--all]"
    command -v jq >/dev/null 2>&1 || die "jq is required for --all"

    SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
    FORGE_ROOT="${FORGE_ROOT:-$HOME/mac-forge}"
    PROJECTS_FILE="${BRAINSTORM_PROJECTS_FILE:-$FORGE_ROOT/config-local/brainstorm-projects.json}"
    [[ -f "$PROJECTS_FILE" ]] || die "Projects file not found: $PROJECTS_FILE"

    paths=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && paths+=("$line")
    done < <(jq -r '.projects[]?' "$PROJECTS_FILE")
    ((${#paths[@]} > 0)) || die "No projects declared in $PROJECTS_FILE"

    ok=0 skipped=0 failed=0
    for p in "${paths[@]}"; do
        p="${p/#\~/$HOME}"
        echo "== $p"
        if [[ ! -d "$p" ]]; then
            echo "✖ Folder not found" >&2
            failed=$((failed + 1))
            continue
        fi
        rc=0
        (cd "$p" && "$SELF") || rc=$?
        case "$rc" in
            0) ok=$((ok + 1)) ;;
            "$EXIT_NOTHING") skipped=$((skipped + 1)) ;;
            *) failed=$((failed + 1)) ;;
        esac
    done

    echo
    echo "Done: $ok archived, $skipped nothing to archive, $failed failed"
    ((failed == 0)) || exit 1
    exit 0
fi

[[ $# -eq 0 ]] || die "Usage: brainstorm-archive [--all]"

ROOT="$PWD"
[[ "$(basename "$ROOT")" == "brainstorm" ]] || die "Run this only from the root of a 'brainstorm' folder (current: $ROOT)"

today="$(date +%F)"

shopt -s nullglob
dirs=()
for d in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]; do
    [[ "$d" == "$today" ]] && continue
    [[ -d "$d" && ! -L "$d" ]] && dirs+=("$d")
done
shopt -u nullglob

if ((${#dirs[@]} == 0)); then
    echo "✖ No archivable date folders (YYYY-MM-DD, excluding today) found in $ROOT" >&2
    exit "$EXIT_NOTHING"
fi

# Glob expansion is lexically sorted, so ISO dates are chronological.
first="${dirs[0]}"
last="${dirs[${#dirs[@]}-1]}"

if [[ "${first:0:7}" == "${last:0:7}" ]]; then
    last_part="${last:8:2}"
else
    last_part="$last"
fi

name="archive-${first}_${last_part}.tar.gz"
target="$ROOT/archive/$name"

mkdir -p "$ROOT/archive"
[[ ! -e "$target" ]] || die "Archive already exists: $target"

tmp="$(mktemp "$ROOT/archive/.tmp-XXXXXX")"
trap 'rm -f "$tmp"' EXIT

echo "Archiving ${#dirs[@]} folder(s): ${dirs[*]}"
tar -czf "$tmp" "${dirs[@]}"
tar -tzf "$tmp" >/dev/null || die "Archive verification failed; folders left untouched"

mv "$tmp" "$target"
trap - EXIT

rm -rf -- "${dirs[@]}"

echo "✔ Created $target"
echo "✔ Removed ${#dirs[@]} archived folder(s)"
