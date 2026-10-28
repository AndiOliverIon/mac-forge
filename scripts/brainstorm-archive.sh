#!/usr/bin/env bash
set -euo pipefail

die() {
    echo "✖ $*" >&2
    exit 1
}

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

((${#dirs[@]} > 0)) || die "No archivable date folders (YYYY-MM-DD, excluding today) found in $ROOT"

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
