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
  convert-mov [-n output_name]

Options:
  -n, --name output_name  Use output_name.gif instead of the selected MOV name.
  -h, --help             Show this help.
EOF
}

output_name=""
while (( $# > 0 )); do
	case "$1" in
		-n|--name)
			shift
			[[ -n "${1:-}" ]] || die "Missing output name after -n."
			output_name="$1"
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

if [[ -n "$output_name" ]]; then
	output_name="${output_name%.gif}"
	[[ -n "$output_name" ]] || die "Output name cannot be empty."
fi

need_cmd fzf
need_cmd ffmpeg
need_cmd gifski

mov_list="$(mktemp)"
ffmpeg_log="$(mktemp)"
gifski_log="$(mktemp)"
cleanup() {
	rm -f "$mov_list" "$ffmpeg_log" "$gifski_log"
}
trap cleanup EXIT

find . -maxdepth 1 -type f -iname '*.mov' -print |
	sed 's#^\./##' |
	LC_ALL=C sort >"$mov_list"

if [[ ! -s "$mov_list" ]]; then
	echo "No .mov files found in: $(pwd)"
	exit 0
fi

preset="$(
	{
		printf "%-22s %s\t%s\n" "standard compression" "fps 10, width 960, quality 70" "standard compression"
		printf "%-22s %s\t%s\n" "high quality" "fps 15, width 1600, quality 95" "high quality"
	} | fzf --prompt="quality> " --height=40% --layout=reverse --border --delimiter=$'\t' --with-nth=1
)" || exit 0

[[ -n "$preset" ]] || exit 0

preset_name="${preset##*$'\t'}"
case "$preset_name" in
	"standard compression")
		fps="10"
		width="960"
		quality="70"
		;;
	"high quality")
		fps="15"
		width="1600"
		quality="95"
		;;
	*)
		die "Unknown preset: $preset_name"
		;;
esac

selected="$(
	fzf --prompt="mov> " --height=60% --layout=reverse --border <"$mov_list"
)" || exit 0

[[ -n "$selected" ]] || exit 0
[[ -f "$selected" ]] || die "Selected file does not exist: $selected"

base="${selected%.*}"
frames_dir="frames"
if [[ -n "$output_name" ]]; then
	output="${output_name}.gif"
else
	output="${base}.gif"
fi

mkdir -p "$frames_dir"

shopt -s nullglob
existing_frames=("$frames_dir"/frame_*.png)
if (( ${#existing_frames[@]} > 0 )); then
	if confirm "Remove ${#existing_frames[@]} existing generated frame(s) from '$frames_dir' before continuing?"; then
		rm -f -- "${existing_frames[@]}"
	else
		die "Stopped to avoid mixing old frames into the GIF."
	fi
fi

if [[ -e "$output" ]]; then
	if confirm "Overwrite existing output '$output'?"; then
		rm -f -- "$output"
	else
		die "Output already exists: $output"
	fi
fi

echo "Extracting frames from '$selected'..."
echo "Preset: $preset_name (fps=$fps, width=$width, quality=$quality)"
echo "ffmpeg -i \"$selected\" -vf \"fps=$fps,scale=$width:-1\" \"$frames_dir/frame_%04d.png\""
if ! ffmpeg -i "$selected" -vf "fps=$fps,scale=$width:-1" "$frames_dir/frame_%04d.png" 2> >(tee "$ffmpeg_log" >&2); then
	echo >&2
	echo "ffmpeg failed. Last output:" >&2
	tail -n 40 "$ffmpeg_log" >&2
	exit 1
fi

frames=("$frames_dir"/*.png)
(( ${#frames[@]} > 0 )) || die "ffmpeg completed but produced no PNG frames."

echo
echo "Encoding GIF '$output'..."
echo "gifski --fps $fps --quality $quality \"$frames_dir\"/*.png -o \"$output\""
if ! gifski --fps "$fps" --quality "$quality" "${frames[@]}" -o "$output" 2> >(tee "$gifski_log" >&2); then
	echo >&2
	echo "gifski failed. Last output:" >&2
	tail -n 40 "$gifski_log" >&2
	exit 1
fi

rm -rf -- "$frames_dir"

echo
echo "Done: $output"
