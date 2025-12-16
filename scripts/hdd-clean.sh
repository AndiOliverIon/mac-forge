#!/usr/bin/env bash
set -euo pipefail

#######################################
# hdd-clean.sh (macOS /bin/bash 3.2 compatible)
# Recursively find old files by extension, list sorted by type+name,
# show summary (>1GB, >5GB), ask confirmation, then permanently delete.
#######################################

usage() {
	cat <<'EOF'
Usage:
  hdd-clean.sh [path] [--for=ext1,ext2,...] [--old=days]

Examples:
  hdd-clean.sh --for=bak,txt --old=31
  hdd-clean.sh /Volumes/shared/sql --for=bak
  hdd-clean.sh --old=90
  hdd-clean.sh               # all files older than 30 days

Notes:
  - If --for is omitted: matches all files (any extension).
  - If --old is omitted: defaults to 30 days.
  - "older than N days" uses find -mtime +N (strictly greater than N*24h).
  - Deletes permanently (rm), does NOT move to Trash.
EOF
}

# Colors (tput-based, terminal-safe)
if command -v tput >/dev/null 2>&1; then
	RESET="$(tput sgr0 || true)"
	BOLD="$(tput bold || true)"
	RED="$(tput setaf 1 || true)"
	GREEN="$(tput setaf 2 || true)"
	YELLOW="$(tput setaf 3 || true)"
	WHITE="$(tput setaf 7 || true)"

	# Orange (256-color if available, else fall back to yellow)
	if [[ "$(tput colors 2>/dev/null || echo 0)" -ge 256 ]]; then
		ORANGE="$(tput setaf 208 || true)"
	else
		ORANGE="$YELLOW"
	fi
else
	RESET=""
	BOLD=""
	RED=""
	GREEN=""
	YELLOW=""
	WHITE=""
	ORANGE=""
fi

# Defaults
TARGET_DIR=""
FOR_EXTS=""
OLD_DAYS="30"

# Parse args
for arg in "$@"; do
	case "$arg" in
		-h | --help)
			usage
			exit 0
			;;
		--for=*)
			FOR_EXTS="${arg#--for=}"
			;;
		--old=*)
			OLD_DAYS="${arg#--old=}"
			;;
		--*)
			echo "Unknown option: $arg" >&2
			usage
			exit 2
			;;
		*)
			if [[ -z "$TARGET_DIR" ]]; then
				TARGET_DIR="$arg"
			else
				echo "Unexpected extra argument: $arg" >&2
				usage
				exit 2
			fi
			;;
	esac
done

if [[ -z "$TARGET_DIR" ]]; then
	TARGET_DIR="."
fi

# Validate
if [[ ! -d "$TARGET_DIR" ]]; then
	echo "Target is not a directory: $TARGET_DIR" >&2
	exit 1
fi

if ! [[ "$OLD_DAYS" =~ ^[0-9]+$ ]]; then
	echo "--old must be an integer number of days. Got: $OLD_DAYS" >&2
	exit 1
fi

TARGET_ABS="$(cd "$TARGET_DIR" && pwd)"
if [[ "$TARGET_ABS" == "/" ]]; then
	echo "Refusing to run on '/'. Choose a specific folder." >&2
	exit 1
fi

# Temp files
files_tmp="$(mktemp)"
rows_tmp="$(mktemp)"
sorted_tmp="$(mktemp)"
summary_tmp="$(mktemp)"
cleanup() {
	rm -f "$files_tmp" "$rows_tmp" "$sorted_tmp" "$summary_tmp"
}
trap cleanup EXIT

# Build find expression
FIND_EXPR=()
if [[ -n "$FOR_EXTS" ]]; then
	IFS=',' read -r -a exts <<<"$FOR_EXTS"

	FIND_EXPR+=("(")
	first=1
	for e in "${exts[@]}"; do
		e="${e#.}"             # strip leading dot
		e="${e//[[:space:]]/}" # remove spaces
		[[ -z "$e" ]] && continue

		if [[ $first -eq 0 ]]; then
			FIND_EXPR+=(-o)
		fi
		first=0
		FIND_EXPR+=(-iname "*.${e}")
	done
	FIND_EXPR+=(")")
fi

# Collect matches (NUL-delimited)
if [[ ${#FIND_EXPR[@]} -gt 0 ]]; then
	find "$TARGET_ABS" -type f -mtime +"$OLD_DAYS" "${FIND_EXPR[@]}" -print0 >"$files_tmp"
else
	find "$TARGET_ABS" -type f -mtime +"$OLD_DAYS" -print0 >"$files_tmp"
fi

# Count results (count NUL bytes)
file_count="$(tr -cd '\0' <"$files_tmp" | wc -c | tr -d ' ')"
if [[ "${file_count:-0}" -eq 0 ]]; then
	echo "No files found in '$TARGET_ABS' older than $OLD_DAYS days."
	exit 0
fi

# Build rows: type \t name \t size_bytes \t mtime_epoch \t path
while IFS= read -r -d '' p; do
	base="$(basename "$p")"

	if [[ "$base" == *.* ]]; then
		type="${base##*.}"
		type="$(printf '%s' "$type" | tr '[:upper:]' '[:lower:]')"
	else
		type="(noext)"
	fi

	size_b="$(stat -f %z -- "$p")"
	mtime_e="$(stat -f %m -- "$p")"

	printf "%s\t%s\t%s\t%s\t%s\n" "$type" "$base" "$size_b" "$mtime_e" "$p" >>"$rows_tmp"
done <"$files_tmp"

# Sort by type then filename
LC_ALL=C sort -t $'\t' -k1,1 -k2,2 "$rows_tmp" >"$sorted_tmp"

echo
echo "Found $file_count file(s) in '$TARGET_ABS' older than $OLD_DAYS day(s)."
if [[ -n "$FOR_EXTS" ]]; then
	echo "Filtered extensions: $FOR_EXTS"
else
	echo "Filtered extensions: (all)"
fi
echo

printf "%-10s  %-10s  %-20s  %s\n" "TYPE" "SIZE" "MODIFIED" "PATH"
printf "%-10s  %-10s  %-20s  %s\n" "----------" "----------" "--------------------" "----"

# Print list
while IFS=$'\t' read -r type name size_b mtime_e path; do
	size_h="$(awk -v b="$size_b" 'function hr(x){
      s="B KB MB GB TB PB"; split(s,a," ");
      i=1; while (x>=1024 && i<6){x/=1024; i++}
      return sprintf("%.1f %s", x, a[i])
    } BEGIN{print hr(b)}')"
	modified="$(date -r "$mtime_e" "+%Y-%m-%d %H:%M:%S")"
	printf "%-10s  %-10s  %-20s  %s\n" "$type" "$size_h" "$modified" "$path"
done <"$sorted_tmp"

# Summary via awk (no associative arrays in bash 3.2)
ONE_GB=$((1024 * 1024 * 1024))
FIVE_GB=$((5 * 1024 * 1024 * 1024))

# Also output __TOTAL__ as the last record (total bytes across all types)
awk -F'\t' -v one="$ONE_GB" -v five="$FIVE_GB" '
{
  t=$1; s=$3+0;
  cnt[t]++; tot[t]+=s;
  grand+=s;
  if(s>one) gt1[t]++;
  if(s>five) gt5[t]++;
}
END{
  for(t in cnt){
    printf "%s\t%d\t%d\t%d\t%.0f\n", t, cnt[t], (gt1[t]+0), (gt5[t]+0), tot[t]
  }
  printf "__TOTAL__\t0\t0\t0\t%.0f\n", grand
}
' "$sorted_tmp" | LC_ALL=C sort -t $'\t' -k1,1 >"$summary_tmp"

echo
echo "${YELLOW}${BOLD}Summary (by type):${RESET}"
printf "%-10s  %8s  %10s  %10s  %14s\n" "TYPE" "COUNT" ">1GB" ">5GB" "TOTAL SIZE"
printf "%-10s  %8s  %10s  %10s  %14s\n" "----------" "--------" "----------" "----------" "--------------"

# Thresholds for coloring by total type size
FIVE_GB_T=$((5 * 1024 * 1024 * 1024))
TWENTY_GB_T=$((20 * 1024 * 1024 * 1024))
THIRTY_GB_T=$((30 * 1024 * 1024 * 1024))

grand_total_bytes="0"

while IFS=$'\t' read -r t c g1 g5 tb; do
	if [[ "$t" == "__TOTAL__" ]]; then
		grand_total_bytes="$tb"
		continue
	fi

	tb_h="$(awk -v b="$tb" 'function hr(x){
      s="B KB MB GB TB PB"; split(s,a," ");
      i=1; while (x>=1024 && i<6){x/=1024; i++}
      return sprintf("%.1f %s", x, a[i])
    } BEGIN{print hr(b)}')"

	# Choose color based on total bytes for this type
	color="$WHITE"
	if ((tb > THIRTY_GB_T)); then
		color="$RED"
	elif ((tb > TWENTY_GB_T)); then
		color="$ORANGE"
	elif ((tb < FIVE_GB_T)); then
		color="$GREEN"
	else
		color="$WHITE"
	fi

	# Colorize only the TOTAL SIZE column (keeps table readable)
	printf "%-10s  %8d  %10d  %10d  %s%14s%s\n" \
		"$t" "$c" "$g1" "$g5" \
		"$color" "$tb_h" "$RESET"
done <"$summary_tmp"

# Grand total (yellow)
grand_total_h="$(awk -v b="$grand_total_bytes" 'function hr(x){
    s="B KB MB GB TB PB"; split(s,a," ");
    i=1; while (x>=1024 && i<6){x/=1024; i++}
    return sprintf("%.1f %s", x, a[i])
  } BEGIN{print hr(b)}')"

echo
echo "${YELLOW}${BOLD}Total space (all matched files): ${grand_total_h}${RESET}"
echo

read -r -p "Confirm permanent delete of ALL listed files? (yes/no): " ans
if [[ "$ans" != "yes" ]]; then
	echo "Cancelled. Nothing deleted."
	exit 0
fi

echo
echo "Deleting..."
deleted=0
while IFS=$'\t' read -r _type _name _size_b _mtime_e path; do
	rm -f -- "$path"
	deleted=$((deleted + 1))
done <"$sorted_tmp"

echo "Done. Deleted $deleted file(s)."
