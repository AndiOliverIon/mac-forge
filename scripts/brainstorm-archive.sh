#!/usr/bin/env bash
set -euo pipefail

die() {
    echo "✖ $*" >&2
    exit 1
}

# Exit code 3 means "nothing to archive" (used by --all to skip quietly).
EXIT_NOTHING=3

# Prints the date (YYYY-MM-DD) that is $1 days before today, on BSD or GNU date.
cutoff_date() {
    date -v-"$1"d +%F 2>/dev/null || date -d "-$1 days" +%F
}

# Last covered date of archive-YYYY-MM-DD_DD(.tar.gz) or archive-YYYY-MM-DD_YYYY-MM-DD(.tar.gz).
archive_end_date() {
    local base="${1%.tar.gz}" first last
    base="${base#archive-}"
    first="${base%%_*}"
    last="${base#*_}"
    [[ "$first" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
    if [[ "$last" =~ ^[0-9]{2}$ ]]; then
        echo "${first:0:8}$last"
    elif [[ "$last" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "$last"
    else
        return 1
    fi
}

# Moves a file to the trash; never falls back to permanent deletion.
move_to_trash() {
    if command -v trash >/dev/null 2>&1; then
        trash "$1"
    elif command -v gio >/dev/null 2>&1; then
        gio trash "$1"
    elif command -v trash-put >/dev/null 2>&1; then
        trash-put "$1"
    elif command -v osascript >/dev/null 2>&1; then
        osascript -e 'on run argv' -e 'tell application "Finder" to delete (POSIX file (item 1 of argv) as alias)' -e 'end run' "$1" >/dev/null
    else
        return 1
    fi
}

# Moves to the trash archives older than $2 days in $1/archive, never touching $3 (archive made this run).
# Prints the trashed file names, one per line.
clean_old_archives() {
    local dir="$1/archive" days="$2" keep="${3:-}" cutoff f end
    [[ -d "$dir" ]] || return 0
    cutoff="$(cutoff_date "$days")"
    for f in "$dir"/archive-*.tar.gz; do
        [[ -f "$f" && ! -L "$f" && "$(basename "$f")" != "$keep" ]] || continue
        end="$(archive_end_date "$(basename "$f")")" || continue
        if [[ "$end" < "$cutoff" ]]; then
            move_to_trash "$f" && basename "$f"
        fi
    done
}

if [[ "${1:-}" == "--all" ]]; then
    [[ $# -eq 1 ]] || die "Usage: brainstorm-archive [--all]"
    command -v jq >/dev/null 2>&1 || die "jq is required for --all"

    SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
    FORGE_ROOT="${FORGE_ROOT:-$HOME/mac-forge}"
    PROJECTS_FILE="${BRAINSTORM_PROJECTS_FILE:-$FORGE_ROOT/config-local/brainstorm-projects.json}"
    [[ -f "$PROJECTS_FILE" ]] || die "Projects file not found: $PROJECTS_FILE"

    # Each project is a path string or {"path": ..., "retentionDays": ...}; the latter overrides the global value.
    paths=()
    retentions=()
    while IFS=$'\t' read -r path days; do
        [[ -n "$path" ]] || continue
        paths+=("$path")
        retentions+=("$days")
    done < <(jq -r '.retentionDays as $g | .projects[]? |
        if type == "string" then [., ($g // "")]
        else [.path, (if has("retentionDays") then (.retentionDays // "") else ($g // "") end)] end
        | map(tostring) | join("\t")' "$PROJECTS_FILE")
    ((${#paths[@]} > 0)) || die "No projects declared in $PROJECTS_FILE"

    if [[ -t 1 ]]; then
        GREEN=$'\033[32m' ORANGE=$'\033[38;5;208m' RED=$'\033[31m' RESET=$'\033[0m'
    else
        GREEN="" ORANGE="" RED="" RESET=""
    fi

    results=()
    ok=0 skipped=0 failed=0 cleaned=0
    for i in "${!paths[@]}"; do
        p="${paths[$i]}"
        days="${retentions[$i]}"
        p="${p/#\~/$HOME}"
        name="$(basename "$(dirname "$p")")"
        if [[ ! -d "$p" ]]; then
            results+=("${RED}✖ $name — folder not found: $p${RESET}")
            failed=$((failed + 1))
            continue
        fi
        rc=0
        out="$( (cd "$p" && "$SELF") 2>&1 )" || rc=$?
        created=""
        case "$rc" in
            0)
                created="$(basename "$(sed -n 's/^✔ Created //p' <<<"$out" | head -n 1)")"
                results+=("${GREEN}✔ $name — $created${RESET}")
                ok=$((ok + 1))
                ;;
            "$EXIT_NOTHING")
                results+=("${ORANGE}– $name — nothing to archive${RESET}")
                skipped=$((skipped + 1))
                ;;
            *)
                results+=("${RED}✖ $name — $(tail -n 1 <<<"$out" | sed 's/^✖ //')${RESET}")
                failed=$((failed + 1))
                ;;
        esac

        # Retention of 0 or empty disables cleanup; only valid brainstorm roots are cleaned.
        if [[ "$rc" == 0 || "$rc" == "$EXIT_NOTHING" ]] && [[ -n "$days" && "$days" != 0 ]]; then
            if [[ "$days" =~ ^[0-9]+$ ]]; then
                removed=()
                while IFS= read -r f; do
                    [[ -n "$f" ]] && removed+=("$f")
                done < <(clean_old_archives "$p" "$days" "$created")
                if ((${#removed[@]} > 0)); then
                    for f in "${removed[@]}"; do
                        results+=("${RED}    🗑  $name — trashed $f (older than $days days)${RESET}")
                    done
                    cleaned=$((cleaned + ${#removed[@]}))
                fi
            else
                results+=("${RED}✖ $name — invalid retentionDays: $days${RESET}")
                failed=$((failed + 1))
            fi
        fi
    done

    printf '%s\n' "${results[@]}"
    echo
    echo "Done: $ok archived, $skipped nothing to archive, $failed failed, $cleaned old archive(s) moved to trash"
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
