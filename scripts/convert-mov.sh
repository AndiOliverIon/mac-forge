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
  convert-mov [-n output_name] [-o]

Options:
  -n, --name output_name  Use output_name.gif instead of the selected MOV name.
  -o, --optimize          Drop near-duplicate frames (ffmpeg mpdecimate) to shrink
                          the GIF. Mid-clip pauses keep their timing via a
                          variable frame-rate encode; a static tail at the very
                          end is not held full-length (GIF limitation). Uses
                          ffmpeg directly (not gifski).
  -h, --help             Show this help.
EOF
}

output_name=""
optimize=0
while (( $# > 0 )); do
	case "$1" in
		-n|--name)
			shift
			[[ -n "${1:-}" ]] || die "Missing output name after -n."
			output_name="$1"
			;;
		-o|--o|--optimize)
			optimize=1
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
need_cmd ffprobe
(( optimize == 1 )) || need_cmd gifski

mov_list="$(mktemp)"
ffmpeg_log="$(mktemp)"
gifski_log="$(mktemp)"
palette="$(mktemp -u).png"
cleanup() {
	rm -f "$mov_list" "$ffmpeg_log" "$gifski_log" "$palette"
}
trap cleanup EXIT

find . -maxdepth 1 -type f -iname '*.mov' -print |
	sed 's#^\./##' |
	LC_ALL=C sort >"$mov_list"

if [[ ! -s "$mov_list" ]]; then
	echo "No .mov files found in: $(pwd)"
	exit 0
fi

# Single readable-quality preset. gifski caps output to ~800x600 unless it is
# given an explicit --width, so width is computed from the source and passed to
# both ffmpeg (frame extraction) and gifski (encode) to avoid silent downscaling.
fps="15"
quality="100"

selected="$(
	fzf --prompt="mov> " --height=60% --layout=reverse --border <"$mov_list"
)" || exit 0

[[ -n "$selected" ]] || exit 0
[[ -f "$selected" ]] || die "Selected file does not exist: $selected"

src_width="$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$selected" | head -n1)"
[[ "$src_width" =~ ^[0-9]+$ ]] || die "Could not determine source width for '$selected'."
# Half-resolution keeps text sharp on Retina captures while halving pixel count.
width=$(( (src_width / 2 / 2) * 2 ))
(( width >= 2 )) || width=$(( (src_width / 2) * 2 ))

base="${selected%.*}"
frames_dir="frames"
if [[ -n "$output_name" ]]; then
	output="${output_name}.gif"
else
	output="${base}.gif"
fi

if [[ -e "$output" ]]; then
	if confirm "Overwrite existing output '$output'?"; then
		rm -f -- "$output"
	else
		die "Output already exists: $output"
	fi
fi

if (( optimize == 1 )); then
	# Optimize path: drop near-duplicate frames with mpdecimate and encode a
	# variable frame-rate GIF so playback timing is preserved (a long static
	# section becomes one long-held frame instead of speeding up). Caveat: GIF
	# has no defined duration for the final frame, so a static section at the very
	# end of the clip is not held for its full original time. gifski is not used
	# here because it only emits constant frame delays.
	echo "Optimizing GIF from '$selected' (near-duplicate frame removal)..."
	echo "Quality: fps=$fps, width=$width (from source ${src_width}px), mpdecimate + VFR"

	echo "Pass 1/2: generating palette..."
	if ! ffmpeg -i "$selected" \
		-vf "fps=$fps,scale=$width:-2:flags=lanczos,palettegen=stats_mode=diff" \
		-y "$palette" 2> >(tee "$ffmpeg_log" >&2); then
		echo >&2
		echo "ffmpeg (palettegen) failed. Last output:" >&2
		tail -n 40 "$ffmpeg_log" >&2
		exit 1
	fi

	echo "Pass 2/2: encoding deduplicated GIF..."
	if ! ffmpeg -i "$selected" -i "$palette" \
		-lavfi "fps=$fps,scale=$width:-2:flags=lanczos,mpdecimate[v];[v][1:v]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
		-fps_mode vfr -y "$output" 2> >(tee "$ffmpeg_log" >&2); then
		echo >&2
		echo "ffmpeg (paletteuse) failed. Last output:" >&2
		tail -n 40 "$ffmpeg_log" >&2
		exit 1
	fi

	echo
	echo "Done: $output"
	exit 0
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

echo "Extracting frames from '$selected'..."
echo "Quality: fps=$fps, width=$width (from source ${src_width}px), quality=$quality"
echo "ffmpeg -i \"$selected\" -vf \"fps=$fps,scale=$width:-2:flags=lanczos\" \"$frames_dir/frame_%04d.png\""
if ! ffmpeg -i "$selected" -vf "fps=$fps,scale=$width:-2:flags=lanczos" "$frames_dir/frame_%04d.png" 2> >(tee "$ffmpeg_log" >&2); then
	echo >&2
	echo "ffmpeg failed. Last output:" >&2
	tail -n 40 "$ffmpeg_log" >&2
	exit 1
fi

frames=("$frames_dir"/*.png)
(( ${#frames[@]} > 0 )) || die "ffmpeg completed but produced no PNG frames."

echo
echo "Encoding GIF '$output'..."
echo "gifski --fps $fps --quality $quality --width $width \"$frames_dir\"/*.png -o \"$output\""
if ! gifski --fps "$fps" --quality "$quality" --width "$width" "${frames[@]}" -o "$output" 2> >(tee "$gifski_log" >&2); then
	echo >&2
	echo "gifski failed. Last output:" >&2
	tail -n 40 "$gifski_log" >&2
	exit 1
fi

rm -rf -- "$frames_dir"

echo
echo "Done: $output"
