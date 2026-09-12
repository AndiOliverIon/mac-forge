#!/usr/bin/env bash
set -euo pipefail

#######################################
# journal - a small personal key/value journal stored as nested JSON in
#           config-local/journal.json.
#
#   journal add   (jadd)  Prompt for title/value/description and store an entry.
#                         A slash-separated title nests the entry, e.g.
#                         'personal/general/wifi' stores 'wifi' inside chapter
#                         'general' inside folder 'personal'.
#   journal rm    (jrm)   fzf multi-select (Tab) entries across chapters and
#                         delete them after typing 'delete' to confirm.
#   journal ls    (jls)   Print every entry as a tree. Optional args narrow it:
#                         'jls <chapter>' keeps entries under matching chapters,
#                         'jls <chapter> <entry>' also filters entries.
#   journal edit  (jedit) fzf-pick an entry and edit its title/value/
#                         description; changing the title moves the entry.
#######################################

die() {
	echo "✖ $*" >&2
	exit 1
}

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."
}

require_cmd jq

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_ROOT="${FORGE_ROOT:-$(cd -- "$SCRIPT_DIR/.." && pwd)}"
CONFIG_LOCAL_DIR="${FORGE_CONFIG_LOCAL_DIR:-$FORGE_ROOT/config-local}"
JOURNAL_FILE="${FORGE_JOURNAL_FILE:-$CONFIG_LOCAL_DIR/journal.json}"

ensure_journal_file() {
	mkdir -p "$CONFIG_LOCAL_DIR"
	[[ -f "$JOURNAL_FILE" ]] || echo '{}' >"$JOURNAL_FILE"
	jq -e 'type == "object"' "$JOURNAL_FILE" >/dev/null 2>&1 \
		|| die "Invalid journal file (expected a JSON object): $JOURNAL_FILE"
}

write_journal() {
	# reads new JSON from stdin, writes atomically
	local tmp
	tmp="$(mktemp "${TMPDIR:-/tmp}/journal.XXXXXX")"
	cat >"$tmp"
	jq -e '.' "$tmp" >/dev/null 2>&1 || {
		rm -f "$tmp"
		die "Refusing to write invalid JSON to journal."
	}
	mv "$tmp" "$JOURNAL_FILE"
}

trim() {
	local s="$1"
	s="${s#"${s%%[![:space:]]*}"}"
	s="${s%"${s##*[![:space:]]}"}"
	printf '%s' "$s"
}

# Convert a slash-separated title into a JSON array of trimmed segments.
title_to_path_json() {
	local title
	title="$(trim "$1")"
	[[ -n "$title" ]] || die "Title is required."

	local -a segs=()
	local IFS='/'
	read -ra raw_segs <<<"$title"
	unset IFS
	local seg
	for seg in "${raw_segs[@]}"; do
		seg="$(trim "$seg")"
		[[ -n "$seg" ]] || die "Title has an empty segment; use non-empty names separated by '/'."
		segs+=("$seg")
	done
	((${#segs[@]} > 0)) || die "Title is required."

	printf '%s\n' "${segs[@]}" | jq -R . | jq -s .
}

# Echo the first prefix path that already points at an entry/scalar (blocks nesting).
prefix_conflict() {
	local file="$1" path_json="$2"
	jq -r --argjson path "$path_json" '
		first(
			range(0; ($path | length) - 1) as $i
			| ($path[0:$i+1]) as $pre
			| (getpath($pre)) as $v
			| select($v != null and (($v | type) != "object" or ($v | has("value"))))
			| ($pre | join("/"))
		) // ""
	' "$file"
}

# Echo the kind of node at a path: none | entry | chapter | scalar.
node_kind() {
	local file="$1" path_json="$2"
	jq -r --argjson path "$path_json" '
		(getpath($path)) as $v
		| if $v == null then "none"
		  elif ($v | type) == "object" and ($v | has("value")) then "entry"
		  elif ($v | type) == "object" then "chapter"
		  else "scalar" end
	' "$file"
}

#######################################
# journal add
#######################################
journal_add() {
	ensure_journal_file

	local title value description
	read -r -p "Title (e.g. personal/general/wifi): " title
	title="$(trim "$title")"
	[[ -n "$title" ]] || die "Title is required."

	local path_json
	path_json="$(title_to_path_json "$title")"

	read -r -p "Value: " value
	[[ -n "$value" ]] || die "Value is required."
	read -r -p "Description (optional): " description

	local bad_prefix
	bad_prefix="$(prefix_conflict "$JOURNAL_FILE" "$path_json")"
	[[ -z "$bad_prefix" ]] || die "Cannot nest under '$bad_prefix' because it is already an entry."

	local target_kind
	target_kind="$(node_kind "$JOURNAL_FILE" "$path_json")"

	case "$target_kind" in
	chapter | scalar)
		die "'$title' already exists as a chapter; choose a different title."
		;;
	entry)
		read -r -p "'$title' already exists. Overwrite? [y/N] " confirm
		[[ "$confirm" =~ ^[Yy]$ ]] || die "Aborted."
		;;
	esac

	jq \
		--argjson path "$path_json" \
		--arg value "$value" \
		--arg desc "$description" \
		'setpath($path; {value: $value} + (if $desc == "" then {} else {description: $desc} end))' \
		"$JOURNAL_FILE" | write_journal

	echo "✔ Saved '$title'."
}

#######################################
# journal ls
#######################################
copy_to_clipboard() {
	local data="$1"
	if command -v pbcopy >/dev/null 2>&1; then
		printf '%s' "$data" | pbcopy
	elif command -v wl-copy >/dev/null 2>&1; then
		printf '%s' "$data" | wl-copy
	elif command -v xclip >/dev/null 2>&1; then
		printf '%s' "$data" | xclip -selection clipboard
	elif command -v xsel >/dev/null 2>&1; then
		printf '%s' "$data" | xsel --clipboard --input
	elif command -v clip.exe >/dev/null 2>&1; then
		printf '%s' "$data" | clip.exe
	elif command -v clip >/dev/null 2>&1; then
		printf '%s' "$data" | clip
	else
		die "No clipboard tool found (need pbcopy, wl-copy, xclip, xsel or clip)."
	fi
}

resolve_python() {
	# Echo a working Python 3 interpreter, skipping the Windows Store alias stub.
	local cand
	for cand in "${FORGE_PYTHON:-}" python3 python; do
		[[ -n "$cand" ]] || continue
		command -v "$cand" >/dev/null 2>&1 || continue
		[[ "$("$cand" -c 'print(1)' 2>/dev/null)" == "1" ]] || continue
		printf '%s' "$cand"
		return 0
	done
	return 1
}

render_journal() {
	# mode: tree | rows ; JOURNAL_COLOR: 1|0
	local mode="$1"
	local py
	py="$(resolve_python)" || die "Python 3 is required for 'jls' but was not found (tried python3, python). Install Python 3 or set FORGE_PYTHON."
	JOURNAL_MODE="$mode" "$py" - "$JOURNAL_FILE" <<'PY'
import json, os, sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as handle:
        data = json.load(handle)
except FileNotFoundError:
    data = {}

mode = os.environ.get("JOURNAL_MODE", "tree")

if not isinstance(data, dict) or not data:
    if mode == "tree":
        print("(journal is empty)")
    sys.exit(0)

# rows mode always colors the display column (fzf renders it with --ansi).
USE_COLOR = mode == "rows" or os.environ.get("JOURNAL_COLOR") == "1"

C_TREE = "90"       # dim gray connectors
C_CHAPTER = "1;34"  # bold blue folders/chapters
C_KEY = "1;36"      # bold cyan entry names
C_VALUE = "32"      # green values
C_DESC = "2;37"     # dim description


def paint(text, code):
    return f"\033[{code}m{text}\033[0m" if USE_COLOR else text


def is_entry(value):
    return isinstance(value, dict) and "value" in value


CHAPTER_FILTER = os.environ.get("JOURNAL_FILTER_CHAPTER", "").strip().lower()
ENTRY_FILTER = os.environ.get("JOURNAL_FILTER_ENTRY", "").strip().lower()


def collect_leaves(node, trail=()):
    for key in node:
        value = node[key]
        path = trail + (key,)
        if is_entry(value):
            yield path, value
        elif isinstance(value, dict):
            yield from collect_leaves(value, path)


if CHAPTER_FILTER or ENTRY_FILTER:
    included = []
    for path, entry in collect_leaves(data):
        ancestors = path[:-1]
        leaf = path[-1]
        chapter_ok = not CHAPTER_FILTER or any(
            CHAPTER_FILTER in seg.lower() for seg in ancestors
        )
        haystack = " ".join(
            [leaf, str(entry.get("value", "")), str(entry.get("description", ""))]
        ).lower()
        entry_ok = not ENTRY_FILTER or ENTRY_FILTER in haystack
        if chapter_ok and entry_ok:
            included.append((path, entry))

    filtered = {}
    for path, entry in included:
        node = filtered
        for seg in path[:-1]:
            node = node.setdefault(seg, {})
        node[path[-1]] = entry
    data = filtered

    if not data:
        if mode == "tree":
            print("(no matching journal entries)")
        sys.exit(0)


def emit(display, kind="chapter", title="", value="", description=""):
    if mode == "rows":
        print("\t".join([display, kind, title, value, description]))
    else:
        print(display)


def render(node, prefix="", trail=()):
    keys = sorted(node.keys())
    for index, key in enumerate(keys):
        value = node[key]
        last = index == len(keys) - 1
        connector = paint("└── " if last else "├── ", C_TREE)
        child_prefix = prefix + paint("    " if last else "│   ", C_TREE)
        path = trail + (key,)
        title = "/".join(path)
        if is_entry(value):
            val = value.get("value", "")
            description = value.get("description", "") or ""
            display = f"{prefix}{connector}{paint(key, C_KEY)} = {paint(val, C_VALUE)}"
            emit(display, "entry", title, val, description)
            if description:
                desc_display = f"{child_prefix}  {paint('(' + description + ')', C_DESC)}"
                emit(desc_display, "entry", title, val, description)
        else:
            emit(f"{prefix}{connector}{paint(key, C_CHAPTER)}", "chapter", title)
            if isinstance(value, dict):
                render(value, child_prefix, path)


render(data)
PY
}

journal_ls() {
	if [[ ! -f "$JOURNAL_FILE" ]]; then
		echo "(journal is empty)"
		return 0
	fi

	# Optional positional filters: <chapter> [entry].
	export JOURNAL_FILTER_CHAPTER="${1:-}"
	export JOURNAL_FILTER_ENTRY="${2:-}"

	# Non-interactive fallback: no TTY or no fzf -> just print the tree.
	if [[ ! -t 1 ]] || ! command -v fzf >/dev/null 2>&1; then
		local color=0
		[[ -t 1 && -z "${NO_COLOR:-}" ]] && color=1
		JOURNAL_COLOR="$color" render_journal tree
		return 0
	fi

	local rows
	rows="$(render_journal rows)"
	[[ -n "${rows//$'\n'/}" ]] || {
		if [[ -n "$JOURNAL_FILTER_CHAPTER$JOURNAL_FILTER_ENTRY" ]]; then
			echo "(no matching journal entries)"
		else
			echo "(journal is empty)"
		fi
		return 0
	}

	local selected
	selected="$(
		printf '%s\n' "$rows" \
			| fzf --ansi --no-sort \
				--delimiter='\t' --with-nth=1 \
				--prompt='jls (type to filter) > ' \
				--height=80% --reverse --border \
				--preview 'printf "title:       %s\nvalue:       %s\ndescription: %s\n" {3} {4} {5}' \
				--preview-window='down,3,wrap'
	)" || true

	[[ -n "$selected" ]] || return 0

	local kind title value description
	kind="$(printf '%s' "$selected" | cut -f2)"
	title="$(printf '%s' "$selected" | cut -f3)"
	value="$(printf '%s' "$selected" | cut -f4)"
	description="$(printf '%s' "$selected" | cut -f5)"

	if [[ "$kind" != "entry" ]]; then
		echo "'${title}' is a chapter; nothing to copy."
		return 0
	fi

	local choice
	choice="$(
		printf '%s\n' value title description all \
			| fzf --prompt="Copy '${title}' to clipboard > " \
				--height=~40% --reverse --border
	)" || true
	[[ -n "$choice" ]] || return 0

	local payload
	case "$choice" in
	value) payload="$value" ;;
	title) payload="$title" ;;
	description) payload="$description" ;;
	all) payload="Title: ${title}"$'\n'"Value: ${value}"$'\n'"Description: ${description}" ;;
	*) die "Unknown copy option '$choice'." ;;
	esac

	copy_to_clipboard "$payload"
	echo "✔ Copied ${choice} of '${title}' to clipboard."
}

#######################################
# journal rm
#######################################
journal_rm() {
	require_cmd fzf
	[[ -f "$JOURNAL_FILE" ]] || die "Journal is empty; nothing to remove."

	local rows
	rows="$(
		jq -r '
			paths(type == "object" and has("value")) as $p
			| [($p | join("/")), (getpath($p).value // ""), (getpath($p).description // "")]
			| @tsv
		' "$JOURNAL_FILE"
	)"
	[[ -n "${rows//$'\n'/}" ]] || die "Journal is empty; nothing to remove."

	local selected
	selected="$(
		printf '%s\n' "$rows" \
			| fzf --multi \
				--delimiter='\t' --with-nth=1 \
				--prompt='jrm (Tab to multi-select) > ' \
				--height=60% --reverse --border \
				--preview 'printf "value:       %s\ndescription: %s\n" {2} {3}' \
			| cut -f1
	)" || true

	[[ -n "${selected//$'\n'/}" ]] || die "Nothing selected."

	local -a paths=()
	local line
	while IFS= read -r line; do
		[[ -n "$line" ]] || continue
		paths+=("$line")
	done <<<"$selected"

	echo
	echo "About to delete ${#paths[@]} entr$([[ ${#paths[@]} -eq 1 ]] && echo y || echo ies):"
	printf '  - %s\n' "${paths[@]}"
	echo
	read -r -p "Type 'delete' to confirm: " confirm
	[[ "$confirm" == "delete" ]] || die "Aborted."

	local dels_json
	dels_json="$(printf '%s\n' "${paths[@]}" | jq -R 'split("/")' | jq -s .)"

	jq --argjson dels "$dels_json" '
		delpaths($dels)
		| walk(if type == "object" then with_entries(select((.value | type) != "object" or (.value != {}))) else . end)
	' "$JOURNAL_FILE" | write_journal

	echo "✔ Deleted ${#paths[@]} entr$([[ ${#paths[@]} -eq 1 ]] && echo y || echo ies)."
}

#######################################
# journal edit
#######################################
journal_edit() {
	require_cmd fzf
	[[ -f "$JOURNAL_FILE" ]] || die "Journal is empty; nothing to edit."

	local rows
	rows="$(render_journal rows)"
	[[ -n "${rows//$'\n'/}" ]] || die "Journal is empty; nothing to edit."

	local selected
	selected="$(
		printf '%s\n' "$rows" \
			| fzf --ansi --no-sort \
				--delimiter='\t' --with-nth=1 \
				--prompt='jedit (pick entry) > ' \
				--height=80% --reverse --border \
				--preview 'printf "title:       %s\nvalue:       %s\ndescription: %s\n" {3} {4} {5}' \
				--preview-window='down,3,wrap'
	)" || true
	[[ -n "$selected" ]] || return 0

	local kind cur_title cur_value cur_desc
	kind="$(printf '%s' "$selected" | cut -f2)"
	cur_title="$(printf '%s' "$selected" | cut -f3)"
	cur_value="$(printf '%s' "$selected" | cut -f4)"
	cur_desc="$(printf '%s' "$selected" | cut -f5)"
	[[ "$kind" == "entry" ]] || die "'$cur_title' is a chapter; pick an entry to edit."

	echo "Editing '$cur_title'. Press Enter to keep the current value; type '-' to clear the description."
	local new_title new_value new_desc
	read -r -p "Title [$cur_title]: " new_title
	new_title="$(trim "$new_title")"
	[[ -n "$new_title" ]] || new_title="$cur_title"

	read -r -p "Value [$cur_value]: " new_value
	[[ -n "$new_value" ]] || new_value="$cur_value"

	read -r -p "Description [${cur_desc:-<none>}]: " new_desc
	if [[ -z "$new_desc" ]]; then
		new_desc="$cur_desc"
	elif [[ "$new_desc" == "-" ]]; then
		new_desc=""
	fi

	local new_path_json old_path_json
	new_path_json="$(title_to_path_json "$new_title")"
	old_path_json="$(title_to_path_json "$cur_title")"

	# Base state used for validation and the final write.
	local state_file="$JOURNAL_FILE"
	local tmp_state=""
	if [[ "$new_title" != "$cur_title" ]]; then
		tmp_state="$(mktemp "${TMPDIR:-/tmp}/journal.XXXXXX")"
		# Remove the old entry first so a move can't collide with itself.
		jq --argjson old "$old_path_json" '
			delpaths([$old])
			| walk(if type == "object" then with_entries(select((.value | type) != "object" or (.value != {}))) else . end)
		' "$JOURNAL_FILE" >"$tmp_state"
		state_file="$tmp_state"

		local bad_prefix
		bad_prefix="$(prefix_conflict "$state_file" "$new_path_json")"
		if [[ -n "$bad_prefix" ]]; then
			rm -f "$tmp_state"
			die "Cannot nest under '$bad_prefix' because it is already an entry."
		fi

		local target_kind
		target_kind="$(node_kind "$state_file" "$new_path_json")"
		case "$target_kind" in
		chapter | scalar)
			rm -f "$tmp_state"
			die "'$new_title' already exists as a chapter; choose a different title."
			;;
		entry)
			read -r -p "'$new_title' already exists. Overwrite? [y/N] " confirm
			if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
				rm -f "$tmp_state"
				die "Aborted."
			fi
			;;
		esac
	fi

	jq \
		--argjson path "$new_path_json" \
		--arg value "$new_value" \
		--arg desc "$new_desc" \
		'setpath($path; {value: $value} + (if $desc == "" then {} else {description: $desc} end))' \
		"$state_file" | write_journal

	[[ -n "$tmp_state" ]] && rm -f "$tmp_state"

	if [[ "$new_title" != "$cur_title" ]]; then
		echo "✔ Updated and moved '$cur_title' -> '$new_title'."
	else
		echo "✔ Updated '$new_title'."
	fi
}

#######################################
# Dispatch
#######################################
action="${1:-}"
[[ $# -gt 0 ]] && shift || true

case "$action" in
add) journal_add "$@" ;;
rm) journal_rm "$@" ;;
ls) journal_ls "$@" ;;
edit) journal_edit "$@" ;;
*) die "Usage: journal <add|rm|ls|edit>" ;;
esac
