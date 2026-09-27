#!/usr/bin/env bash

set -euo pipefail

DEFAULT_COWORKER="artanis"
DEFAULT_REVIEWER="argus"
DEFAULT_MAX_CYCLES=5

die() {
	printf 'Error: %s\n' "$*" >&2
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
                         Required. If a loop is paused for Oliver, this is the
                         decision that resumes its recorded sessions.
  --coworker <identity>  artanis, karax, argus, or aegis. Default: artanis.
  --reviewer <identity>  artanis, karax, argus, or aegis. Default: argus.
  --max-cycles <count>   Maximum review cycles before Oliver is required. Default: 5.
  -h, --help             Show this help.

The repository is the canonical Git repository containing the current directory.
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

iso_timestamp() {
	date '+%Y-%m-%dT%H:%M:%S%z'
}

new_uuid() {
	command -v uuidgen >/dev/null 2>&1 || die "uuidgen is required for persistent agent sessions."
	uuidgen | tr '[:upper:]' '[:lower:]'
}

coworker="$DEFAULT_COWORKER"
reviewer="$DEFAULT_REVIEWER"
max_cycles="$DEFAULT_MAX_CYCLES"
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
		shift 2
		;;
	--coworker=*)
		coworker="$(normalize_identity "${1#*=}")"
		shift
		;;
	--reviewer)
		(($# >= 2)) || die "--reviewer requires a value."
		reviewer="$(normalize_identity "$2")"
		shift 2
		;;
	--reviewer=*)
		reviewer="$(normalize_identity "${1#*=}")"
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
	[[ ! -L "$lane_directory" && -d "$lane_directory" ]] ||
		die "MasterChief handoff lane is missing or unsafe: $lane_directory"
	;;
*) die "Unsupported station for team workflow: ${station:-unknown}" ;;
esac

request_file="$lane_directory/request-$coworker.md"
findings_file="$lane_directory/findings-$coworker.md"
state_file="$lane_directory/team-loop-$coworker.json"
state_coworker_slug="$coworker"
resume_loop=false
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
		;;
	awaiting-oliver | cycle-limit-awaiting-oliver)
		resume_loop=true
		;;
	esac
fi

if [[ -e "$request_file" ]]; then
	require_regular_file "$request_file"
	existing_repository="$(header_value "$request_file" "Repository")"
	[[ -z "$existing_repository" || "$existing_repository" == "$repository" ]] ||
		die "The existing $coworker request belongs to another repository: $existing_repository"
fi
[[ ! -e "$findings_file" ]] || require_regular_file "$findings_file"

umask 077
runtime_directory="$(mktemp -d "${TMPDIR:-/tmp}/team-work.XXXXXX")"
state_initialized=false
finished=false

cleanup() {
	local exit_code=$?
	trap - EXIT INT TERM

	if [[ "$state_initialized" == true && "$finished" != true && -f "$state_file" ]]; then
		state_temp="$(mktemp "$lane_directory/.team-loop-state.XXXXXX")"
		jq --arg status "failed" --arg updated "$(iso_timestamp)" \
			'.status = $status | .updatedAt = $updated' "$state_file" >"$state_temp" &&
			chmod 600 "$state_temp" &&
			mv "$state_temp" "$state_file"
	fi
	if [[ -n "${runtime_directory:-}" && -d "$runtime_directory" ]]; then
		rm -rf -- "$runtime_directory"
	fi
	exit "$exit_code"
}
trap cleanup EXIT INT TERM

if [[ "$resume_loop" == true ]]; then
	loop_id="$(jq -r '.loopId // empty' "$state_file")"
	state_repository="$(jq -r '.repository // empty' "$state_file")"
	coworker_display="$(jq -r '.coworker // empty' "$state_file")"
	reviewer_display="$(jq -r '.reviewer // empty' "$state_file")"
	coworker="$(normalize_identity "$coworker_display")"
	reviewer="$(normalize_identity "$reviewer_display")"
	coworker_session="$(jq -r '.coworkerSessionId // empty' "$state_file")"
	reviewer_session="$(jq -r '.reviewerSessionId // empty' "$state_file")"
	current_cycle="$(jq -r '.cycle // 0' "$state_file")"
	stored_max_cycles="$(jq -r '.maxCycles // 0' "$state_file")"
	started_at="$(jq -r '.startedAt // empty' "$state_file")"

	[[ -n "$loop_id" ]] || die "Paused team loop has no loop ID."
	[[ "$state_repository" == "$repository" ]] ||
		die "Paused team loop belongs to another repository: ${state_repository:-missing}"
	display_identity "$coworker" >/dev/null || die "Paused loop has an invalid Coworker."
	display_identity "$reviewer" >/dev/null || die "Paused loop has an invalid Reviewer."
	[[ "$coworker" == "$state_coworker_slug" ]] ||
		die "Paused loop Coworker does not match its state filename."
	[[ "$coworker" != "$reviewer" ]] || die "Paused loop participants are not distinct."
	[[ -n "$coworker_session" ]] || die "Paused loop has no Coworker session ID."
	[[ "$current_cycle" =~ ^[1-9][0-9]*$ ]] || die "Paused loop has an invalid cycle."
	[[ "$stored_max_cycles" =~ ^[1-9][0-9]*$ ]] || die "Paused loop has an invalid cycle limit."
	if ((stored_max_cycles > max_cycles)); then
		max_cycles="$stored_max_cycles"
	fi
	start_cycle=$((current_cycle + 1))
	if [[ "$(header_value "$request_file" "Status")" == "awaiting-oliver" ]]; then
		start_cycle="$current_cycle"
	fi
	if ((start_cycle > max_cycles)); then
		max_cycles="$start_cycle"
	fi
else
	loop_id="team:$station:$lane:$coworker:$(date -u '+%Y%m%dT%H%M%SZ')"
	started_at="$(iso_timestamp)"
	coworker_display="$(display_identity "$coworker")"
	reviewer_display="$(display_identity "$reviewer")"
	coworker_session=""
	reviewer_session=""
	start_cycle=1
fi

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

RUN_SESSION_ID=""

run_agent() {
	local identity="$1"
	local session_id="$2"
	local agent_prompt="$3"
	local prompt_file="$runtime_directory/prompt-$identity.txt"
	local raw_output="$runtime_directory/output-$identity.json"
	local last_message="$runtime_directory/last-$identity.txt"
	local generated_session="$session_id"
	local exit_code=0

	printf '%s\n' "$agent_prompt" >"$prompt_file"
	: >"$raw_output"
	: >"$last_message"

	printf '\nRunning %s (%s)...\n' "$(display_identity "$identity")" "$(identity_command "$identity")"

	case "$identity" in
	artanis)
		if [[ -z "$session_id" ]]; then
			codex exec --json --color never -C "$repository" \
				--sandbox workspace-write --add-dir "$lane_directory" \
				--ask-for-approval never --output-last-message "$last_message" - \
				<"$prompt_file" >"$raw_output" || exit_code=$?
			generated_session="$(jq -r 'select(.type == "thread.started") | .thread_id' "$raw_output" | head -n 1)"
		else
			codex exec resume --json --output-last-message "$last_message" "$session_id" - \
				<"$prompt_file" >"$raw_output" || exit_code=$?
		fi
		;;
	argus)
		if [[ -z "$session_id" ]]; then
			generated_session="$(new_uuid)"
			claude --print --output-format json --session-id "$generated_session" \
				--permission-mode auto --permission-prompts none \
				--add-dir "$lane_directory" "$agent_prompt" \
				>"$raw_output" || exit_code=$?
		else
			claude --print --output-format json --resume "$session_id" \
				--permission-mode auto --permission-prompts none \
				--add-dir "$lane_directory" "$agent_prompt" \
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

	if [[ -s "$last_message" ]]; then
		printf '%s\n' "$(display_identity "$identity") completed the turn:"
		sed -n '1,40p' "$last_message"
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
	ready-for-review | awaiting-oliver) printf '%s\n' "$status" ;;
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
	approved | changes-required | discussion-required) printf '%s\n' "$verdict" ;;
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

if [[ "$resume_loop" == true ]]; then
	state_initialized=true
	update_state "working-coworker" "$start_cycle"
	printf 'Team loop resumed\n\n'
else
	write_initial_state
	printf 'Team loop started\n\n'
fi

printf 'Loop ID: %s\n' "$loop_id"
printf 'Repository: %s\n' "$repository"
printf 'Coworker: %s (%s)\n' "$coworker_display" "$(identity_command "$coworker")"
printf 'Reviewer: %s (%s)\n' "$reviewer_display" "$(identity_command "$reviewer")"
printf 'Maximum cycles: %s\n' "$max_cycles"

for ((cycle = start_cycle; cycle <= max_cycles; cycle++)); do
	update_state "working-coworker" "$cycle"
	if [[ "$resume_loop" == true && "$cycle" == "$start_cycle" ]]; then
		run_agent "$coworker" "$coworker_session" "$(coworker_resume_prompt "$cycle")"
		resume_loop=false
	elif ((cycle == 1)); then
		run_agent "$coworker" "$coworker_session" "$(initial_coworker_prompt)"
	else
		run_agent "$coworker" "$coworker_session" "$(coworker_followup_prompt "$cycle")"
	fi
	coworker_session="$RUN_SESSION_ID"

	request_status="$(validate_request "$cycle")"
	if [[ "$request_status" == "awaiting-oliver" ]]; then
		update_state "awaiting-oliver" "$cycle"
		finished=true
		printf '\nTeam loop paused for Oliver.\nRequest: %s\n' "$request_file"
		exit 0
	fi

	update_state "awaiting-reviewer" "$cycle"
	run_agent "$reviewer" "$reviewer_session" "$(reviewer_prompt "$cycle")"
	reviewer_session="$RUN_SESSION_ID"

	verdict="$(validate_findings "$cycle")"
	case "$verdict" in
	approved)
		update_state "approved-awaiting-oliver" "$cycle"
		finished=true
		printf '\nTeam loop approved by %s and returned to Oliver.\n' "$reviewer_display"
		printf 'Request: %s\nFindings: %s\n' "$request_file" "$findings_file"
		exit 0
		;;
	discussion-required)
		update_state "awaiting-oliver" "$cycle"
		finished=true
		printf '\nTeam loop paused for Oliver because discussion is required.\n'
		printf 'Findings: %s\n' "$findings_file"
		exit 0
		;;
	changes-required)
		if ((cycle == max_cycles)); then
			update_state "cycle-limit-awaiting-oliver" "$cycle"
			finished=true
			printf '\nTeam loop reached its %s-cycle limit and paused for Oliver.\n' "$max_cycles"
			printf 'Findings: %s\n' "$findings_file"
			exit 0
		fi
		update_state "awaiting-coworker" "$cycle"
		;;
	esac
done
