#!/usr/bin/env bash

set -euo pipefail

DEFAULT_COWORKER="artanis"
DEFAULT_REVIEWER="argus"
DEFAULT_MAX_CYCLES=5

record_transcript_failure() {
	local message="$1"
	local file="${transcript_file:-}"

	[[ "${transcript_ready:-false}" == true && -n "$file" && ! -L "$file" && -f "$file" ]] ||
		return 0
	{
		printf '## %s — Coordinator failure\n\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
		printf '%s\n\n' "$message"
	} >>"$file" 2>/dev/null || true
}

die() {
	local message="$*"

	printf 'Error: %s\n' "$message" >&2
	record_transcript_failure "$message"
	exit 1
}

usage() {
	cat <<'EOF'
Run an autonomous review loop between two real AI team-member sessions.
This is an opt-in addition to the existing manual handoff flow.

Usage:
  team-work.sh --prompt <task> [options]

Options:
  --prompt <task>        Task, acceptance criteria, scope, and validation authority.
                         Required. The running coordinator asks for later
                         decisions directly in the same terminal; enter /stop
                         at that prompt to end the loop without approval.
  --coworker <identity>  artanis, karax, argus, or aegis. Default: artanis.
  --reviewer <identity>  artanis, karax, argus, or aegis. Default: argus.
                         When neither --coworker nor --reviewer is given, an fzf
                         chooser offers the team pairs (default first, then the
                         other Artanis/Argus pairing, then the Aegis pairings).
  --max-cycles <count>   Maximum review cycles before Oliver is required. Default: 5.
  -h, --help             Show this help.

The repository is the canonical Git repository containing the current directory.
Each started task writes one task-named Markdown transcript in the handoff lane.
EOF
}

normalize_identity() {
	printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]'
}

display_identity() {
	case "$1" in
	artanis) printf 'Artanis\n' ;;
	karax) printf 'Karax\n' ;;
	argus) printf 'Argus\n' ;;
	aegis) printf 'Aegis\n' ;;
	*) return 1 ;;
	esac
}

identity_command() {
	case "$1" in
	artanis) printf 'codex\n' ;;
	karax) printf 'grok\n' ;;
	argus) printf 'claude\n' ;;
	aegis) printf 'copilot\n' ;;
	*) return 1 ;;
	esac
}

header_value() {
	local file="$1"
	local label="$2"

	awk -v prefix="- $label: " 'index($0, prefix) == 1 { print substr($0, length(prefix) + 1); exit }' "$file"
}

require_regular_file() {
	local file="$1"

	[[ ! -L "$file" && -f "$file" ]] || die "Expected a physical regular file: $file"
}

require_header() {
	local file="$1"
	local label="$2"
	local expected="$3"
	local actual

	actual="$(header_value "$file" "$label")"
	[[ "$actual" == "$expected" ]] ||
		die "$label mismatch in $file (expected '$expected', found '${actual:-missing}')."
}

physical_directory() {
	cd -P "$1" 2>/dev/null && pwd
}

task_filename_slug() {
	local value

	value="$(printf '%s\n' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//' | cut -c1-40)"
	value="${value%-}"
	printf '%s\n' "${value:-task}"
}

is_routine_local_change() {
	local path="$1"
	local pattern

	case "$path" in
	local-overrides/* | */local-overrides/* | wwwroot/license/offline/currentModuleRestrictionList.json | wwwroot/license/offline/currentModuleRestrictionList.original.json | */wwwroot/license/offline/currentModuleRestrictionList.json | */wwwroot/license/offline/currentModuleRestrictionList.original.json)
		return 0
		;;
	esac

	while IFS= read -r pattern; do
		[[ -n "$pattern" ]] || continue
		if [[ "$path" == $pattern ]]; then
			return 0
		fi
	done < <(git config --local --get-all team-work.allowedDirtyPath 2>/dev/null || true)

	return 1
}

assert_safe_initial_worktree() {
	local entry status path origin
	local -a blocking_changes=()

	while IFS= read -r -d '' entry; do
		status="${entry:0:2}"
		path="${entry:3}"
		origin=""
		case "$status" in
		[RC]? | ?[RC])
			IFS= read -r -d '' origin || true
			;;
		esac

		is_routine_local_change "$path" || blocking_changes+=("$status $path")
		if [[ -n "$origin" ]]; then
			is_routine_local_change "$origin" || blocking_changes+=("$status $origin")
		fi
	done < <(git status --porcelain=v1 -z --untracked-files=all)

	if ((${#blocking_changes[@]} > 0)); then
		printf 'Pending repository changes require Oliver\047s decision before team work starts:\n' >&2
		printf '  %s\n' "${blocking_changes[@]}" >&2
		printf 'Resolve them, or mark a genuinely routine local path with:\n' >&2
		printf '  git config --local --add team-work.allowedDirtyPath \047path/or/glob\047\n' >&2
		die "Team workflow did not start."
	fi
}

iso_timestamp() {
	date '+%Y-%m-%dT%H:%M:%S%z'
}

new_uuid() {
	command -v uuidgen >/dev/null 2>&1 || die "uuidgen is required for persistent agent sessions."
	uuidgen | tr '[:upper:]' '[:lower:]'
}

choose_team() {
	command -v fzf >/dev/null 2>&1 || return 1

	local -a pairs=(
		"artanis argus"
		"argus artanis"
		"artanis aegis"
		"aegis artanis"
		"argus aegis"
		"aegis argus"
	)

	local -a menu=()
	local index=1 pair cw rv label suffix
	for pair in "${pairs[@]}"; do
		cw="${pair%% *}"
		rv="${pair##* }"
		suffix=""
		((index == 1)) && suffix="  [default]"
		label="$(printf '%d) %s (coworker) / %s (reviewer)%s' "$index" \
			"$(display_identity "$cw")" "$(display_identity "$rv")" "$suffix")"
		menu+=("$label")
		index=$((index + 1))
	done

	local selection
	selection="$(printf '%s\n' "${menu[@]}" |
		fzf --prompt='Select team> ' --height=40% --reverse --no-multi)" || return 1
	[[ -n "$selection" ]] || return 1

	local chosen_index="${selection%%)*}"
	[[ "$chosen_index" =~ ^[1-9][0-9]*$ ]] && ((chosen_index <= ${#pairs[@]})) || return 1
	local chosen="${pairs[$((chosen_index - 1))]}"
	coworker="${chosen%% *}"
	reviewer="${chosen##* }"
	return 0
}

coworker="$DEFAULT_COWORKER"
reviewer="$DEFAULT_REVIEWER"
max_cycles="$DEFAULT_MAX_CYCLES"
coworker_set=false
reviewer_set=false
prompt=""

while (($# > 0)); do
	case "$1" in
	--prompt)
		(($# >= 2)) || die "--prompt requires a value."
		prompt="$2"
		shift 2
		;;
	--prompt=*)
		prompt="${1#*=}"
		shift
		;;
	--coworker)
		(($# >= 2)) || die "--coworker requires a value."
		coworker="$(normalize_identity "$2")"
		coworker_set=true
		shift 2
		;;
	--coworker=*)
		coworker="$(normalize_identity "${1#*=}")"
		coworker_set=true
		shift
		;;
	--reviewer)
		(($# >= 2)) || die "--reviewer requires a value."
		reviewer="$(normalize_identity "$2")"
		reviewer_set=true
		shift 2
		;;
	--reviewer=*)
		reviewer="$(normalize_identity "${1#*=}")"
		reviewer_set=true
		shift
		;;
	--max-cycles)
		(($# >= 2)) || die "--max-cycles requires a value."
		max_cycles="$2"
		shift 2
		;;
	--max-cycles=*)
		max_cycles="${1#*=}"
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*) die "Unknown option: $1" ;;
	esac
done

[[ -n "${prompt//[[:space:]]/}" ]] || die "--prompt is required and must not be empty."
if [[ "$coworker_set" == false && "$reviewer_set" == false ]]; then
	choose_team || true
fi
display_identity "$coworker" >/dev/null || die "Unknown coworker identity: $coworker"
display_identity "$reviewer" >/dev/null || die "Unknown reviewer identity: $reviewer"
[[ "$coworker" != "$reviewer" ]] || die "Coworker and Reviewer must be different identities."
[[ "$max_cycles" =~ ^[1-9][0-9]*$ ]] || die "--max-cycles must be a positive integer."

command -v git >/dev/null 2>&1 || die "git is required."
command -v jq >/dev/null 2>&1 || die "jq is required."

repository="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)" ||
	die "Run team-work from inside a Git repository."
repository="$(physical_directory "$repository")" ||
	die "Cannot resolve the physical repository root."
cd "$repository"
assert_safe_initial_worktree

project_key="$(basename "$repository")"
[[ "$project_key" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] ||
	die "Unsafe repository basename for a handoff lane: $project_key"

station="$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)"
station="${station%%.*}"
station="$(printf '%s\n' "$station" | tr '[:upper:]' '[:lower:]')"

case "$station" in
hades)
	lane="$project_key"
	handoff_root="/Users/oliver/handoffserver"
	lane_directory="$handoff_root/$lane"

	[[ ! -L "$handoff_root" ]] || die "Handoff root must not be a symlink: $handoff_root"
	if [[ ! -e "$handoff_root" ]]; then
		mkdir -m 700 "$handoff_root"
	fi
	[[ -d "$handoff_root" ]] || die "Handoff root is not a directory: $handoff_root"
	if [[ ! -e "$lane_directory" ]]; then
		mkdir -m 700 "$lane_directory"
	fi
	[[ ! -L "$lane_directory" && -d "$lane_directory" ]] ||
		die "Handoff lane must be a physical directory: $lane_directory"
	chmod 700 "$handoff_root" "$lane_directory"

	handoff_root_physical="$(physical_directory "$handoff_root")"
	lane_physical="$(physical_directory "$lane_directory")"
	[[ "$(dirname "$lane_physical")" == "$handoff_root_physical" ]] ||
		die "Handoff lane is not an immediate child of the handoff root."

	for existing_request in "$lane_directory"/request-*.md; do
		[[ -e "$existing_request" ]] || continue
		require_regular_file "$existing_request"
		existing_repository="$(header_value "$existing_request" "Repository")"
		[[ -z "$existing_repository" || "$existing_repository" == "$repository" ]] ||
			die "Handoff lane basename collision with repository: $existing_repository"
	done
	;;
masterchief)
	case "$repository/" in
	/home/oliver/work/*)
		lane="work"
		lane_directory="/home/oliver/work/.ai/review-handoff"
		;;
	/home/oliver/raynor/*)
		lane="raynor"
		lane_directory="/home/oliver/raynor/.ai/review-handoff"
		;;
	/home/oliver/zeratul/*)
		lane="zeratul"
		lane_directory="/home/oliver/zeratul/.ai/review-handoff"
		;;
	*) die "Repository is outside the supported MasterChief lanes: $repository" ;;
	esac
	case "$lane" in
	work)
		[[ -z "${FORGE_UNIVERSE_ROOT:-}" ]] ||
			die "The Work lane requires a shell without FORGE_UNIVERSE_ROOT."
		;;
	raynor | zeratul)
		expected_universe_root="/home/oliver/$lane"
		[[ -n "${FORGE_UNIVERSE_ROOT:-}" ]] ||
			die "The $lane lane requires FORGE_UNIVERSE_ROOT=$expected_universe_root."
		actual_universe_root="$(physical_directory "$FORGE_UNIVERSE_ROOT")" ||
			die "Cannot resolve FORGE_UNIVERSE_ROOT: $FORGE_UNIVERSE_ROOT"
		[[ "$actual_universe_root" == "$expected_universe_root" ]] ||
			die "The $lane lane conflicts with FORGE_UNIVERSE_ROOT=$actual_universe_root."
		;;
	esac
	[[ ! -L "$lane_directory" && -d "$lane_directory" ]] ||
		die "MasterChief handoff lane is missing or unsafe: $lane_directory"
	;;
*) die "Unsupported station for team workflow: ${station:-unknown}" ;;
esac

lane_physical="$(physical_directory "$lane_directory")" ||
	die "Cannot resolve the physical handoff lane: $lane_directory"
transcript_directory="$lane_directory/transcripts"
if [[ ! -e "$transcript_directory" ]]; then
	mkdir -m 700 "$transcript_directory"
fi
[[ ! -L "$transcript_directory" && -d "$transcript_directory" ]] ||
	die "Transcript path must be a physical directory: $transcript_directory"
transcript_physical="$(physical_directory "$transcript_directory")" ||
	die "Cannot resolve transcript directory: $transcript_directory"
[[ "$(dirname "$transcript_physical")" == "$lane_physical" ]] ||
	die "Transcript directory is not an immediate child of the handoff lane."
chmod 700 "$transcript_directory"

request_file="$lane_directory/request-$coworker.md"
findings_file="$lane_directory/findings-$coworker.md"
state_file="$lane_directory/team-loop-$coworker.json"
previous_status=""

if [[ -e "$state_file" ]]; then
	[[ ! -L "$state_file" && -f "$state_file" ]] ||
		die "Team-loop state must be a physical regular file: $state_file"
	previous_status="$(jq -r '.status // "unknown"' "$state_file" 2>/dev/null || printf 'invalid')"
	previous_pid="$(jq -r '.coordinatorPid // 0' "$state_file" 2>/dev/null || printf '0')"
	case "$previous_status" in
	working-coworker | awaiting-reviewer | awaiting-coworker)
		if [[ "$previous_pid" =~ ^[1-9][0-9]*$ ]] && kill -0 "$previous_pid" 2>/dev/null; then
			die "An active team loop already owns the $coworker transporter pair (PID $previous_pid)."
		fi
		die "A stale $previous_status team loop requires recovery before a new task can start. Inspect and move aside $state_file first."
		;;
	approved-awaiting-oliver | stopped-by-oliver)
		;;
	failed | awaiting-oliver | cycle-limit-awaiting-oliver | unknown | invalid)
		die "Existing team-loop state '$previous_status' requires recovery before a new task can start. Inspect and move aside $state_file first."
		;;
	*)
		die "Unexpected team-loop state '$previous_status' in $state_file."
		;;
	esac
fi

if [[ -e "$request_file" ]]; then
	require_regular_file "$request_file"
	existing_repository="$(header_value "$request_file" "Repository")"
	[[ -z "$existing_repository" || "$existing_repository" == "$repository" ]] ||
		die "The existing $coworker request belongs to another repository: $existing_repository"
	request_status="$(header_value "$request_file" "Status")"
	request_automation="$(header_value "$request_file" "Automation")"
	request_handoff_id="$(header_value "$request_file" "Handoff ID")"
	if [[ "$request_status" == "ready-for-review" && "$request_automation" != "team-loop" ]]; then
		findings_handoff_id=""
		findings_status=""
		if [[ -e "$findings_file" ]]; then
			require_regular_file "$findings_file"
			findings_handoff_id="$(header_value "$findings_file" "Handoff ID")"
			findings_status="$(header_value "$findings_file" "Status")"
		fi
		[[ -n "$request_handoff_id" && "$findings_status" == "review-complete" && "$findings_handoff_id" == "$request_handoff_id" ]] ||
			die "A pending manual handoff owns the $coworker transporter pair."
	fi
fi
[[ ! -e "$findings_file" ]] || require_regular_file "$findings_file"

umask 077
runtime_directory="$(mktemp -d "${TMPDIR:-/tmp}/team-work.XXXXXX")"
state_initialized=false
finished=false
transcript_ready=false
transcript_owned=false
task_started_token="$(date -u '+%Y%m%dT%H%M%SZ')"
loop_id="team:$station:$lane:$coworker:$task_started_token"
started_at="$(iso_timestamp)"
coworker_display="$(display_identity "$coworker")"
reviewer_display="$(display_identity "$reviewer")"
coworker_session=""
reviewer_session=""
transcript_slug="$(task_filename_slug "$prompt")"
transcript_file="$transcript_directory/$transcript_slug-$task_started_token.md"
transcript_suffix=2
transcript_allocation=""

append_transcript_message() {
	local speaker="$1"
	local body="$2"

	require_regular_file "$transcript_file"
	{
		printf '## %s — %s\n\n' "$(iso_timestamp)" "$speaker"
		printf '%s\n\n' "$body"
	} >>"$transcript_file"
}

append_transcript_file() {
	local title="$1"
	local file="$2"

	require_regular_file "$transcript_file"
	require_regular_file "$file"
	{
		printf '## %s — %s\n\n' "$(iso_timestamp)" "$title"
		sed 's/^/    /' "$file"
		printf '\n'
	} >>"$transcript_file"
}

cleanup() {
	local incoming_status=$?
	local exit_code="${1:-$incoming_status}"
	local stop_reason="${2:-exit status $exit_code}"
	trap - EXIT INT TERM

	if [[ "$finished" != true && "$transcript_owned" == true && ! -L "$transcript_file" && -f "$transcript_file" ]]; then
		(
			append_transcript_message "Coordinator" "The workflow stopped with $stop_reason before approval or Oliver's /stop."
		) 2>/dev/null || true
	fi
	if [[ "$state_initialized" == true && "$finished" != true && ! -L "$state_file" && -f "$state_file" ]]; then
		(
			state_temp="$(mktemp "$lane_directory/.team-loop-state.XXXXXX")"
			jq --arg status "failed" --arg updated "$(iso_timestamp)" \
				'.status = $status | .updatedAt = $updated' "$state_file" >"$state_temp" &&
				chmod 600 "$state_temp" &&
				mv "$state_temp" "$state_file"
		) 2>/dev/null || true
	fi
	if [[ -n "${transcript_allocation:-}" && ! -L "$transcript_allocation" && -f "$transcript_allocation" ]]; then
		rm -f -- "$transcript_allocation" || true
	fi
	if [[ -n "${runtime_directory:-}" && -d "$runtime_directory" ]]; then
		rm -rf -- "$runtime_directory" || true
	fi
	exit "$exit_code"
}
trap cleanup EXIT
trap 'cleanup 130 "signal INT"' INT
trap 'cleanup 143 "signal TERM"' TERM

transcript_allocation="$(mktemp "$transcript_directory/.transcript.XXXXXX")"
while :; do
	if [[ -e "$transcript_file" || -L "$transcript_file" ]]; then
		transcript_file="$transcript_directory/$transcript_slug-$task_started_token-$transcript_suffix.md"
		transcript_suffix=$((transcript_suffix + 1))
		continue
	fi
	if ln -n "$transcript_allocation" "$transcript_file" 2>/dev/null; then
		transcript_owned=true
		break
	fi
	[[ -e "$transcript_file" || -L "$transcript_file" ]] ||
		die "Cannot create transcript: $transcript_file"
done
rm -f -- "$transcript_allocation"
transcript_allocation=""
require_regular_file "$transcript_file"

{
	printf '# Team Workflow Transcript\n\n'
	printf -- '- Task: %s\n' "$transcript_slug"
	printf -- '- Started: %s\n' "$started_at"
	printf -- '- Loop ID: %s\n' "$loop_id"
	printf -- '- Station: %s\n' "$station"
	printf -- '- Lane: %s\n' "$lane"
	printf -- '- Repository: %s\n' "$repository"
	printf -- '- Coworker: %s\n' "$coworker_display"
	printf -- '- Reviewer: %s\n\n' "$reviewer_display"
} >>"$transcript_file"
chmod 600 "$transcript_file"
transcript_ready=true
append_transcript_message "Oliver" "$prompt"

command -v "$(identity_command "$coworker")" >/dev/null 2>&1 ||
	die "$(identity_command "$coworker") is required for $coworker_display."
command -v "$(identity_command "$reviewer")" >/dev/null 2>&1 ||
	die "$(identity_command "$reviewer") is required for $reviewer_display."

write_initial_state() {
	local state_temp

	state_temp="$(mktemp "$lane_directory/.team-loop-state.XXXXXX")"
	jq -n \
		--arg loopId "$loop_id" \
		--arg status "working-coworker" \
		--arg station "$station" \
		--arg lane "$lane" \
		--arg repository "$repository" \
		--arg coworker "$coworker_display" \
		--arg reviewer "$reviewer_display" \
		--arg requestFile "$request_file" \
		--arg findingsFile "$findings_file" \
		--arg transcriptFile "$transcript_file" \
		--arg startedAt "$started_at" \
		--argjson maxCycles "$max_cycles" \
		--argjson coordinatorPid "$$" \
		'{
			schemaVersion: 1,
			loopId: $loopId,
			status: $status,
			station: $station,
			lane: $lane,
			repository: $repository,
			coworker: $coworker,
			reviewer: $reviewer,
			maxCycles: $maxCycles,
			cycle: 1,
			coworkerSessionId: "",
			reviewerSessionId: "",
			requestFile: $requestFile,
			findingsFile: $findingsFile,
			transcriptFile: $transcriptFile,
			coordinatorPid: $coordinatorPid,
			startedAt: $startedAt,
			updatedAt: $startedAt
		}' >"$state_temp"
	chmod 600 "$state_temp"
	mv "$state_temp" "$state_file"
	state_initialized=true
}

update_state() {
	local status="$1"
	local cycle="$2"
	local state_temp

	state_temp="$(mktemp "$lane_directory/.team-loop-state.XXXXXX")"
	jq \
		--arg status "$status" \
		--arg updated "$(iso_timestamp)" \
		--arg coworkerSession "$coworker_session" \
		--arg reviewerSession "$reviewer_session" \
		--argjson maxCycles "$max_cycles" \
		--argjson coordinatorPid "$$" \
		--argjson cycle "$cycle" \
		'.status = $status
		 | .cycle = $cycle
		 | .coworkerSessionId = $coworkerSession
		 | .reviewerSessionId = $reviewerSession
		 | .maxCycles = $maxCycles
		 | .coordinatorPid = $coordinatorPid
		 | .updatedAt = $updated' "$state_file" >"$state_temp"
	chmod 600 "$state_temp"
	mv "$state_temp" "$state_file"
}

repository_fingerprint() {
	local snapshot="$runtime_directory/repository-snapshot-$RANDOM"
	local path

	git status --porcelain=v2 -z --untracked-files=all >"$snapshot"
	git diff --binary HEAD >>"$snapshot"
	while IFS= read -r -d '' path; do
		printf '\0%s\0' "$path" >>"$snapshot"
		git hash-object -- "$path" >>"$snapshot"
	done < <(git ls-files --others --exclude-standard -z)
	git hash-object "$snapshot"
	rm -f -- "$snapshot"
}

repository_refs_fingerprint() {
	local snapshot="$runtime_directory/repository-refs-$RANDOM"

	git symbolic-ref -q HEAD >"$snapshot" 2>/dev/null || git rev-parse HEAD >"$snapshot"
	git for-each-ref --format='%(refname) %(objectname)' >>"$snapshot"
	git hash-object "$snapshot"
	rm -f -- "$snapshot"
}

OLIVER_DECISION=""

wait_for_oliver() {
	local reason="$1"

	[[ -t 0 ]] || die "Oliver's decision is required, but team-work is not attached to an interactive terminal."
	append_transcript_message "Coordinator" "The workflow is waiting for Oliver: $reason"
	printf '\nTeam loop is waiting for Oliver: %s\n' "$reason" >&2
	while :; do
		printf 'Decision: ' >&2
		IFS= read -r OLIVER_DECISION || die "No decision was received; the loop is stopping as failed."
		[[ -n "${OLIVER_DECISION//[[:space:]]/}" ]] && break
		printf 'Enter a non-empty decision.\n' >&2
	done
	append_transcript_message "Oliver" "$OLIVER_DECISION"
	if [[ "$OLIVER_DECISION" == "/stop" ]]; then
		update_state "stopped-by-oliver" "$cycle"
		append_transcript_message "Coordinator" "Oliver stopped the workflow without approval."
		finished=true
		printf '\nTeam loop stopped by Oliver without approval.\n' >&2
		printf 'Transcript: %s\n' "$transcript_file" >&2
		exit 0
	fi
}

RUN_SESSION_ID=""
VALIDATED_REQUEST_STATUS=""
VALIDATED_VERDICT=""

run_agent() {
	local identity="$1"
	local session_id="$2"
	local agent_prompt="$3"
	local prompt_file="$runtime_directory/prompt-$identity.txt"
	local raw_output="$runtime_directory/output-$identity.json"
	local last_message="$runtime_directory/last-$identity.txt"
	local generated_session="$session_id"
	local exit_code=0
	local transcript_before_turn

	printf '%s\n' "$agent_prompt" >"$prompt_file"
	: >"$raw_output"
	: >"$last_message"

	append_transcript_message "Input to $(display_identity "$identity") — cycle $cycle" "$agent_prompt"
	transcript_before_turn="$(git hash-object "$transcript_file")"
	printf '\nRunning %s (%s)...\n' "$(display_identity "$identity")" "$(identity_command "$identity")"

	case "$identity" in
	artanis)
		if [[ -z "$session_id" ]]; then
			codex -a never exec --json --color never -C "$repository" \
				--sandbox workspace-write --add-dir "$lane_directory" \
				--output-last-message "$last_message" - \
				<"$prompt_file" >"$raw_output" || exit_code=$?
			generated_session="$(jq -r 'select(.type == "thread.started") | .thread_id' "$raw_output" | head -n 1)"
		else
			codex -a never --sandbox workspace-write --add-dir "$lane_directory" \
				exec resume --json --output-last-message "$last_message" "$session_id" - \
				<"$prompt_file" >"$raw_output" || exit_code=$?
		fi
		;;
	argus)
		if [[ -z "$session_id" ]]; then
			generated_session="$(new_uuid)"
			claude --print --output-format json --session-id "$generated_session" \
				--permission-mode auto --permission-prompts none \
				--add-dir "$lane_directory" <"$prompt_file" \
				>"$raw_output" || exit_code=$?
		else
			claude --print --output-format json --resume "$session_id" \
				--permission-mode auto --permission-prompts none \
				--add-dir "$lane_directory" <"$prompt_file" \
				>"$raw_output" || exit_code=$?
		fi
		jq -r '.result // empty' "$raw_output" >"$last_message" 2>/dev/null || true
		;;
	karax)
		if [[ -z "$session_id" ]]; then
			generated_session="$(new_uuid)"
			grok --single "$agent_prompt" --output-format json --session-id "$generated_session" \
				--cwd "$repository" --permission-mode auto --no-subagents \
				>"$raw_output" || exit_code=$?
		else
			grok --single "$agent_prompt" --output-format json --resume "$session_id" \
				--cwd "$repository" --permission-mode auto --no-subagents \
				>"$raw_output" || exit_code=$?
		fi
		jq -r '.result // .message // empty' "$raw_output" >"$last_message" 2>/dev/null || true
		;;
	aegis)
		if [[ -z "$session_id" ]]; then
			generated_session="$(new_uuid)"
			copilot --prompt "$agent_prompt" --output-format json --session-id "$generated_session" \
				-C "$repository" --allow-all-tools --add-dir "$lane_directory" --no-ask-user \
				>"$raw_output" || exit_code=$?
		else
			copilot --prompt "$agent_prompt" --output-format json --resume "$session_id" \
				-C "$repository" --allow-all-tools --add-dir "$lane_directory" --no-ask-user \
				>"$raw_output" || exit_code=$?
		fi
		jq -r 'select(.type == "assistant.message" or .type == "result") | .content // .message // empty' \
			"$raw_output" >"$last_message" 2>/dev/null || true
		;;
	esac
	[[ "$(git hash-object "$transcript_file")" == "$transcript_before_turn" ]] ||
		die "$(display_identity "$identity") modified the coordinator-owned transcript."

	if [[ -s "$last_message" ]]; then
		append_transcript_file "$(display_identity "$identity") response — cycle $cycle" "$last_message"
		printf '%s\n' "$(display_identity "$identity") completed the turn:"
		sed -n '1,40p' "$last_message"
	else
		append_transcript_message "$(display_identity "$identity") response — cycle $cycle" "No final response was captured (CLI exit status $exit_code)."
	fi

	if ((exit_code != 0)); then
		if [[ -s "$raw_output" ]]; then
			printf '%s\n' "$(display_identity "$identity") output before failure:" >&2
			tail -n 40 "$raw_output" >&2
		fi
		die "$(display_identity "$identity") exited with status $exit_code."
	fi
	[[ -n "$generated_session" && "$generated_session" != "null" ]] ||
		die "Could not determine the persistent session ID for $(display_identity "$identity")."
	RUN_SESSION_ID="$generated_session"
}

validate_request() {
	local cycle="$1"
	local status

	require_regular_file "$request_file"
	chmod 600 "$request_file"
	require_header "$request_file" "Automation" "team-loop"
	require_header "$request_file" "Loop ID" "$loop_id"
	require_header "$request_file" "Cycle" "$cycle"
	require_header "$request_file" "Cycle limit" "$max_cycles"
	require_header "$request_file" "Coworker" "$coworker_display"
	require_header "$request_file" "Reviewer" "$reviewer_display"
	require_header "$request_file" "Repository" "$repository"
	status="$(header_value "$request_file" "Status")"
	case "$status" in
	ready-for-review | awaiting-oliver) VALIDATED_REQUEST_STATUS="$status" ;;
	*) die "Unexpected request status: ${status:-missing}" ;;
	esac
}

validate_findings() {
	local cycle="$1"
	local request_handoff_id
	local verdict

	require_regular_file "$findings_file"
	chmod 600 "$findings_file"
	require_header "$findings_file" "Status" "review-complete"
	require_header "$findings_file" "Automation" "team-loop"
	require_header "$findings_file" "Loop ID" "$loop_id"
	require_header "$findings_file" "Cycle" "$cycle"
	require_header "$findings_file" "Cycle limit" "$max_cycles"
	require_header "$findings_file" "Coworker" "$coworker_display"
	require_header "$findings_file" "Reviewer" "$reviewer_display"
	require_header "$findings_file" "Repository" "$repository"
	request_handoff_id="$(header_value "$request_file" "Handoff ID")"
	[[ -n "$request_handoff_id" ]] || die "Request handoff ID is missing."
	require_header "$findings_file" "Handoff ID" "$request_handoff_id"
	verdict="$(header_value "$findings_file" "Verdict")"
	case "$verdict" in
	approved | changes-required | discussion-required) VALIDATED_VERDICT="$verdict" ;;
	*) die "Unexpected review verdict: ${verdict:-missing}" ;;
	esac
}

initial_coworker_prompt() {
	cat <<EOF
Oliver explicitly authorizes an autonomous team review loop.

- Automation: team-loop
- Loop ID: $loop_id
- Cycle: 1
- Cycle limit: $max_cycles
- Coworker: $coworker_display
- Reviewer: $reviewer_display
- Repository: $repository
- Request file: $request_file
- Findings file: $findings_file
- Transcript file: $transcript_file (coordinator-owned; do not modify)

Task from Oliver:

$prompt

Act only as $coworker_display, the Coworker. Do not spawn, simulate, or invoke the Reviewer or any
other AI identity. Load the routed handoff protocol, then resolve development mode for the actual
target files and load its selected stack and project instructions before editing. Implement the task
within Oliver's stated scope, preserving unrelated existing changes. Do not commit, push, deploy, or
perform destructive actions during this loop. Unit tests remain unauthorized unless Oliver's task
above explicitly authorizes the specific run.

When the implementation and authorized non-test validation are ready, prepare the autonomous review
request for $reviewer_display using the shared handoff protocol. Include the Automation, Loop ID,
Cycle, and Cycle limit headers exactly as given above. If a decision is required before review, write
the request with Status: awaiting-oliver and a precise Escalation section instead. End the turn after
writing the request; the coordinator will invoke the real Reviewer session.
EOF
}

coworker_followup_prompt() {
	local cycle="$1"

	cat <<EOF
Continue Oliver's authorized autonomous team review loop.

- Automation: team-loop
- Loop ID: $loop_id
- Cycle: $cycle
- Cycle limit: $max_cycles
- Coworker: $coworker_display
- Reviewer: $reviewer_display
- Repository: $repository
- Request file: $request_file
- Findings file: $findings_file
- Transcript file: $transcript_file (coordinator-owned; do not modify)

Process $reviewer_display's findings from the immediately preceding cycle. Act only as
$coworker_display. Do not spawn, simulate, or invoke the Reviewer or another AI identity.

Independently classify every finding. Implement confirmed in-scope corrections under Oliver's loop
authorization, but first resolve development mode for the actual correction targets and load its
selected stack and project instructions. For a rejected or partially valid finding, record the
evidence and reasoning in the next request so the real Reviewer can reconsider it. If the finding
requires a business decision, scope expansion, destructive action, unauthorized test, or other
Oliver-only decision, write the request with Status: awaiting-oliver and a precise Escalation
section, then stop.

Otherwise complete authorized validation and replace the request with the next review request.
Include the Automation, Loop ID, Cycle, and Cycle limit headers exactly as given above. Do not
commit, push, or deploy. End the turn after writing the request.
EOF
}

coworker_resume_prompt() {
	local cycle="$1"

	cat <<EOF
Resume Oliver's paused autonomous team review loop in the same real Coworker session.

- Automation: team-loop
- Loop ID: $loop_id
- Cycle: $cycle
- Cycle limit: $max_cycles
- Coworker: $coworker_display
- Reviewer: $reviewer_display
- Repository: $repository
- Request file: $request_file
- Findings file: $findings_file
- Transcript file: $transcript_file (coordinator-owned; do not modify)

Oliver's decision or clarification:

$prompt

Act only as $coworker_display. Do not spawn, simulate, or invoke the Reviewer or another AI
identity. Inspect the existing request, matching findings when present, and the escalation that
caused the pause. Treat Oliver's decision above as authoritative for this loop. Load the routed
handoff protocol, then resolve development mode for any actual edit targets and load its selected
stack and project instructions before editing.

Apply only the work authorized by Oliver's decision. Preserve unrelated changes. Do not commit,
push, deploy, perform destructive actions, or run an unauthorized unit test. Replace the request
with Status: ready-for-review and a new handoff ID when ready, using the Automation, Loop ID, Cycle,
and Cycle limit headers exactly as given above. If Oliver's response does not resolve the blocker,
replace it with Status: awaiting-oliver and a precise Escalation section instead. End the turn after
writing the request.
EOF
}

reviewer_prompt() {
	local cycle="$1"

	cat <<EOF
Process $coworker_display's autonomous review handoff as the real $reviewer_display session.

- Automation: team-loop
- Loop ID: $loop_id
- Cycle: $cycle
- Cycle limit: $max_cycles
- Coworker: $coworker_display
- Reviewer: $reviewer_display
- Repository: $repository
- Request file: $request_file
- Findings file: $findings_file
- Transcript file: $transcript_file (coordinator-owned; do not modify)

Act only as $reviewer_display, the independent Reviewer. Do not spawn, simulate, or invoke the
Coworker or another AI identity. Independently inspect the actual repository target and write the
matching findings file under the shared handoff protocol. Include the Automation, Loop ID, Cycle,
and Cycle limit headers exactly as given above. Never implement repository changes.

Use Verdict: discussion-required when a business decision is ambiguous or when the Coworker has
rejected or only partially accepted a blocking finding and you maintain that it blocks approval.
Use Verdict: approved only when no blocking findings remain. End the turn after writing findings;
the coordinator will invoke the real Coworker session when another cycle is allowed.
EOF
}

write_initial_state
append_transcript_message "Coordinator" "The autonomous team workflow started."
printf 'Team loop started\n\n'

printf 'Loop ID: %s\n' "$loop_id"
printf 'Repository: %s\n' "$repository"
printf 'Coworker: %s (%s)\n' "$coworker_display" "$(identity_command "$coworker")"
printf 'Reviewer: %s (%s)\n' "$reviewer_display" "$(identity_command "$reviewer")"
printf 'Maximum cycles: %s\n' "$max_cycles"
printf 'Transcript: %s\n' "$transcript_file"

cycle=1
coworker_turn="initial"

while :; do
	update_state "working-coworker" "$cycle"
	coworker_refs_before="$(repository_refs_fingerprint)"
	case "$coworker_turn" in
	resume)
		run_agent "$coworker" "$coworker_session" "$(coworker_resume_prompt "$cycle")"
		;;
	initial)
		run_agent "$coworker" "$coworker_session" "$(initial_coworker_prompt)"
		;;
	followup)
		run_agent "$coworker" "$coworker_session" "$(coworker_followup_prompt "$cycle")"
		;;
	esac
	coworker_session="$RUN_SESSION_ID"
	coworker_refs_after="$(repository_refs_fingerprint)"
	if [[ "$coworker_refs_after" != "$coworker_refs_before" ]]; then
		update_state "awaiting-oliver" "$cycle"
		wait_for_oliver "$coworker_display changed repository refs or HEAD during its turn."
		prompt="Coordinator integrity alert: $coworker_display changed repository refs or HEAD. Oliver's decision: $OLIVER_DECISION"
		coworker_turn="resume"
		continue
	fi

	append_transcript_file "$coworker_display review request — cycle $cycle" "$request_file"
	validate_request "$cycle"
	request_status="$VALIDATED_REQUEST_STATUS"
	if [[ "$request_status" == "awaiting-oliver" ]]; then
		update_state "awaiting-oliver" "$cycle"
		wait_for_oliver "the Coworker requested a decision in $request_file."
		prompt="$OLIVER_DECISION"
		coworker_turn="resume"
		continue
	fi

	update_state "awaiting-reviewer" "$cycle"
	reviewer_repository_before="$(repository_fingerprint)"
	reviewer_refs_before="$(repository_refs_fingerprint)"
	run_agent "$reviewer" "$reviewer_session" "$(reviewer_prompt "$cycle")"
	reviewer_session="$RUN_SESSION_ID"
	reviewer_repository_after="$(repository_fingerprint)"
	reviewer_refs_after="$(repository_refs_fingerprint)"
	if [[ "$reviewer_repository_after" != "$reviewer_repository_before" || "$reviewer_refs_after" != "$reviewer_refs_before" ]]; then
		update_state "awaiting-oliver" "$cycle"
		wait_for_oliver "$reviewer_display changed repository state during a read-only review turn."
		prompt="Coordinator integrity alert: $reviewer_display changed repository state during review. Oliver's decision: $OLIVER_DECISION"
		cycle=$((cycle + 1))
		if ((cycle > max_cycles)); then
			max_cycles="$cycle"
		fi
		coworker_turn="resume"
		continue
	fi

	append_transcript_file "$reviewer_display findings — cycle $cycle" "$findings_file"
	validate_findings "$cycle"
	verdict="$VALIDATED_VERDICT"
	append_transcript_message "Coordinator" "$reviewer_display recorded verdict '$verdict' for cycle $cycle."
	case "$verdict" in
	approved)
		update_state "approved-awaiting-oliver" "$cycle"
		append_transcript_message "Coordinator" "The workflow was approved by $reviewer_display and returned to Oliver."
		finished=true
		printf '\nTeam loop approved by %s and returned to Oliver.\n' "$reviewer_display"
		printf 'Request: %s\nFindings: %s\nTranscript: %s\n' "$request_file" "$findings_file" "$transcript_file"
		exit 0
		;;
	discussion-required)
		update_state "awaiting-oliver" "$cycle"
		wait_for_oliver "$reviewer_display requires discussion in $findings_file."
		prompt="$OLIVER_DECISION"
		cycle=$((cycle + 1))
		if ((cycle > max_cycles)); then
			max_cycles="$cycle"
		fi
		coworker_turn="resume"
		;;
	changes-required)
		if ((cycle == max_cycles)); then
			update_state "cycle-limit-awaiting-oliver" "$cycle"
			wait_for_oliver "the loop reached its $max_cycles-cycle limit with changes still required."
			prompt="$OLIVER_DECISION"
			cycle=$((cycle + 1))
			max_cycles="$cycle"
			coworker_turn="resume"
			continue
		fi
		update_state "awaiting-coworker" "$cycle"
		cycle=$((cycle + 1))
		coworker_turn="followup"
		;;
	esac
done
