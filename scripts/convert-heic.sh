#!/usr/bin/env bash
set -euo pipefail

die() {
	echo "Error: $*" >&2
	exit 1
}

need_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."
}

confirm() {
	local prompt="$1"
	local answer

	read -r -p "$prompt [y/N] " answer
	[[ "$answer" == "y" || "$answer" == "Y" ]]
}

usage() {
	cat <<'EOF'
Usage:
  convert-heic [-q quality] [-o]

Converts HEIC images in the current directory to JPG, keeping the same base name.
Presents an fzf list of found .heic files; use Tab to multi-select, Enter to convert.

Options:
  -q, --quality N   JPEG quality 1-100 (default: 95, visually close to original).
  -o, --overwrite   Overwrite existing .jpg outputs without prompting.
  -h, --help        Show this help.
EOF
}

quality="95"
overwrite=0
while (( $# > 0 )); do
	case "$1" in
		-q|--quality)
			shift
			[[ -n "${1:-}" ]] || die "Missing value after -q."
			quality="$1"
			;;
		-o|--overwrite)
			overwrite=1
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			die "Unknown option: $1"
			;;
	esac
	shift
done

[[ "$quality" =~ ^[0-9]+$ ]] && (( quality >= 1 && quality <= 100 )) \
	|| die "Quality must be an integer between 1 and 100."

need_cmd fzf
need_cmd sips

heic_list="$(mktemp)"
cleanup() {
	rm -f "$heic_list"
}
trap cleanup EXIT

find . -maxdepth 1 -type f -iname '*.heic' -print |
	sed 's#^\./##' |
	LC_ALL=C sort >"$heic_list"

if [[ ! -s "$heic_list" ]]; then
	echo "No .heic files found in: $(pwd)"
	exit 0
fi

selected="$(
	fzf --multi \
		--prompt="heic> " \
		--header="Tab to select multiple, Enter to convert" \
		--height=60% --layout=reverse --border <"$heic_list"
)" || exit 0

[[ -n "$selected" ]] || exit 0

converted=0
failed=0
while IFS= read -r file; do
	[[ -n "$file" ]] || continue
	[[ -f "$file" ]] || { echo "Skipping missing file: $file" >&2; failed=$((failed + 1)); continue; }

	output="${file%.*}.jpg"

	if [[ -e "$output" ]] && (( overwrite == 0 )); then
		if ! confirm "Overwrite existing '$output'?"; then
			echo "Skipped: $file"
			continue
		fi
	fi

	echo "Converting '$file' -> '$output' (quality=$quality)..."
	if sips -s format jpeg -s formatOptions "$quality" "$file" --out "$output" >/dev/null 2>&1; then
		converted=$((converted + 1))
	else
		echo "Failed to convert: $file" >&2
		failed=$((failed + 1))
	fi
done <<<"$selected"

echo
echo "Done: $converted converted, $failed failed."
