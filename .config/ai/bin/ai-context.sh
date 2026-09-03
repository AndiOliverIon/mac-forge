#!/usr/bin/env bash

set -eo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AI_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FORGE_ROOT="$(cd "$AI_ROOT/../.." && pwd)"
STATIONS_FILE="$FORGE_ROOT/configs/stations.json"
MODE=""
REPOSITORY_INPUT=""
REVIEW_TARGET=""
TARGET_INPUTS=()
resolved_targets=()
stacks=()
base_instructions=()
project_instructions=()
routed_instructions=()
stack_instructions=()
provisional_instructions=()
next_instructions=()

usage() {
    cat <<'EOF'
Resolve the current AI execution and instruction context.

Usage:
  ai-context.sh --mode <development|review|handoff> [scope]

Scope:
  --repository <path>       Repository or a path inside it.
  --target <path>           File in scope; may be repeated.
  --review-target <target>  HEAD, working-tree, staged, or a Git diff range.

The output contains the resolved execution context, the already-loaded base
instruction paths, and the project/stack instruction paths to load next.
EOF
}

die() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command is unavailable: $1"
}

normalize_hostname() {
    local value="$1"

    value="${value%%.*}"
    printf '%s\n' "$value" | tr '[:upper:]' '[:lower:]'
}

canonical_directory() {
    cd -P "$1" 2>/dev/null && pwd
}

nearest_existing_directory() {
    local candidate="$1"

    [[ "$candidate" == /* ]] || candidate="$(pwd -P)/$candidate"
    [[ -d "$candidate" ]] || candidate="$(dirname "$candidate")"
    while [[ ! -d "$candidate" && "$candidate" != "/" ]]; do
        candidate="$(dirname "$candidate")"
    done
    canonical_directory "$candidate"
}

append_unique() {
    local array_name="$1"
    local value="$2"
    local existing

    case "$array_name" in
        resolved_targets)
            for existing in "${resolved_targets[@]}"; do
                [[ "$existing" == "$value" ]] && return
            done
            resolved_targets[${#resolved_targets[@]}]="$value"
            ;;
        stacks)
            for existing in "${stacks[@]}"; do
                [[ "$existing" == "$value" ]] && return
            done
            stacks[${#stacks[@]}]="$value"
            ;;
        base_instructions)
            for existing in "${base_instructions[@]}"; do
                [[ "$existing" == "$value" ]] && return
            done
            base_instructions[${#base_instructions[@]}]="$value"
            ;;
        project_instructions)
            for existing in "${project_instructions[@]}"; do
                [[ "$existing" == "$value" ]] && return
            done
            project_instructions[${#project_instructions[@]}]="$value"
            ;;
        routed_instructions)
            for existing in "${routed_instructions[@]}"; do
                [[ "$existing" == "$value" ]] && return
            done
            routed_instructions[${#routed_instructions[@]}]="$value"
            ;;
        stack_instructions)
            for existing in "${stack_instructions[@]}"; do
                [[ "$existing" == "$value" ]] && return
            done
            stack_instructions[${#stack_instructions[@]}]="$value"
            ;;
        provisional_instructions)
            for existing in "${provisional_instructions[@]}"; do
                [[ "$existing" == "$value" ]] && return
            done
            provisional_instructions[${#provisional_instructions[@]}]="$value"
            ;;
        next_instructions)
            for existing in "${next_instructions[@]}"; do
                [[ "$existing" == "$value" ]] && return
            done
            next_instructions[${#next_instructions[@]}]="$value"
            ;;
        *) die "internal error: unknown list $array_name" ;;
    esac
}

resolve_target_path() {
    local value="$1"
    local base cursor suffix component canonical_cursor

    if [[ "$value" == /* ]]; then
        base="$value"
    elif [[ -n "$repository_root" ]]; then
        base="$repository_root/$value"
    else
        base="$(pwd -P)/$value"
    fi

    if [[ -d "$base" ]]; then
        canonical_directory "$base"
        return
    fi
    if [[ -e "$base" ]]; then
        printf '%s/%s\n' "$(canonical_directory "$(dirname "$base")")" "$(basename "$base")"
        return
    fi

    cursor="$base"
    suffix=""
    while [[ ! -e "$cursor" && "$cursor" != "/" ]]; do
        component="$(basename "$cursor")"
        suffix="/$component$suffix"
        cursor="$(dirname "$cursor")"
    done
    if [[ -d "$cursor" ]]; then
        canonical_cursor="$(canonical_directory "$cursor")"
    else
        canonical_cursor="$(canonical_directory "$(dirname "$cursor")")/$(basename "$cursor")"
    fi
    printf '%s%s\n' "$canonical_cursor" "$suffix"
}

discover_repository_root() {
    local candidate_directory=""

    if [[ -n "$REPOSITORY_INPUT" ]]; then
        candidate_directory="$(nearest_existing_directory "$REPOSITORY_INPUT")"
    elif ((${#TARGET_INPUTS[@]} > 0)); then
        candidate_directory="$(nearest_existing_directory "${TARGET_INPUTS[0]}")"
    else
        candidate_directory="$(pwd -P)"
    fi

    git -C "$candidate_directory" rev-parse --show-toplevel 2>/dev/null || true
}

discover_station() {
    local hostname_value="$1"

    jq -r --arg hostname "$hostname_value" '
        .stations[]
        | select(any(.identifiers.hostnames[]?;
            ((ascii_downcase | split(".")[0]) == $hostname)))
        | .id
    ' "$STATIONS_FILE" | head -n 1
}

discover_universe() {
    local station="$1"
    local scope_path="$2"
    local configured_count universe

    [[ "$station" != "unresolved" ]] || {
        printf '%s\n' "unresolved"
        return
    }

    configured_count="$(jq -r --arg station "$station" '
        .stations[] | select(.id == $station) | (.agentRuntime.identities // []) | length
    ' "$STATIONS_FILE")"

    if [[ -z "$configured_count" ]]; then
        printf '%s\n' "unresolved"
        return
    elif [[ "$configured_count" == "0" ]]; then
        printf '%s\n' "none"
        return
    fi

    if [[ -n "${FORGE_UNIVERSE_ROOT:-}" ]]; then
        universe="$(jq -r --arg station "$station" --arg root "$FORGE_UNIVERSE_ROOT" '
            .stations[] | select(.id == $station)
            | (.agentRuntime.identities // [])[]
            | select(.universeRoot == $root)
            | .id
        ' "$STATIONS_FILE" | head -n 1)"
    else
        universe="$(jq -r --arg station "$station" --arg path "$scope_path" '
            .stations[] | select(.id == $station)
            | (.agentRuntime.identities // [])[]
            | .universeRoot as $root
            | select(($path == $root) or ($path | startswith($root + "/")))
            | .id
        ' "$STATIONS_FILE" | head -n 1)"
    fi

    printf '%s\n' "${universe:-unresolved}"
}

collect_review_targets() {
    local relative_path

    [[ -n "$REVIEW_TARGET" ]] || return 0
    [[ -n "$repository_root" ]] || die "--review-target requires a resolvable repository"

    case "$REVIEW_TARGET" in
        HEAD)
            while IFS= read -r relative_path; do
                [[ -n "$relative_path" ]] && TARGET_INPUTS+=("$repository_root/$relative_path")
            done < <(git -C "$repository_root" diff-tree --root --no-commit-id --name-only -r HEAD)
            ;;
        working-tree)
            while IFS= read -r relative_path; do
                [[ -n "$relative_path" ]] && TARGET_INPUTS+=("$repository_root/$relative_path")
            done < <({
                git -C "$repository_root" diff --name-only
                git -C "$repository_root" diff --cached --name-only
                git -C "$repository_root" ls-files --others --exclude-standard
            } | LC_ALL=C sort -u)
            ;;
        staged)
            while IFS= read -r relative_path; do
                [[ -n "$relative_path" ]] && TARGET_INPUTS+=("$repository_root/$relative_path")
            done < <(git -C "$repository_root" diff --cached --name-only)
            ;;
        *)
            while IFS= read -r relative_path; do
                [[ -n "$relative_path" ]] && TARGET_INPUTS+=("$repository_root/$relative_path")
            done < <(git -C "$repository_root" diff --name-only "$REVIEW_TARGET")
            ;;
    esac
}

classify_stacks() {
    local target basename_value

    for target in "${resolved_targets[@]}"; do
        basename_value="$(basename "$target")"
        case "$target" in
            *.ts | *.tsx | *.js | *.jsx | *.html | *.scss | *.sass | *.less | *.css)
                append_unique stacks angular
                ;;
            *.cs | *.csproj | *.fs | *.fsproj | *.vb | *.vbproj | *.sln)
                append_unique stacks dotnet
                ;;
            *.sql)
                append_unique stacks sql
                ;;
        esac
        case "$basename_value" in
            Dockerfile | Dockerfile.* | docker-compose.yml | docker-compose.yaml | compose.yml | compose.yaml)
                append_unique stacks ops
                ;;
        esac
    done
}

collect_instruction_directory() {
    local directory="$1"

    if [[ -f "$directory/AGENTS.override.md" ]]; then
        append_unique project_instructions "$directory/AGENTS.override.md"
    elif [[ -f "$directory/AGENTS.md" ]]; then
        append_unique project_instructions "$directory/AGENTS.md"
    fi
    if [[ -f "$directory/CLAUDE.md" ]]; then
        append_unique project_instructions "$directory/CLAUDE.md"
    fi
}

collect_project_instructions() {
    local target target_directory cursor directories index

    [[ -n "$repository_root" ]] || return 0
    collect_instruction_directory "$repository_root"

    for target in "${resolved_targets[@]}"; do
        target_directory="$target"
        [[ -d "$target_directory" ]] || target_directory="$(dirname "$target_directory")"
        cursor="$target_directory"
        directories=()
        while [[ "$cursor" != "$repository_root" && "$cursor" == "$repository_root"/* ]]; do
            directories+=("$cursor")
            cursor="$(dirname "$cursor")"
        done
        for ((index=${#directories[@]} - 1; index >= 0; index--)); do
            collect_instruction_directory "${directories[index]}"
        done
    done
}

corpus_matches() {
    local pattern="$1"

    printf '%s\n' "$selection_corpus" | grep -Ei "$pattern" >/dev/null
}

select_angular_review_topics() {
    local target

    [[ "$MODE" == "review" ]] || return 0
    selection_corpus="$({
        for target in "${resolved_targets[@]}"; do
            printf '%s\n' "$target"
            [[ -f "$target" ]] && cat "$target"
        done

        if [[ -n "$REVIEW_TARGET" && -n "$repository_root" ]]; then
            case "$REVIEW_TARGET" in
                HEAD)
                    git -C "$repository_root" show --format= --no-ext-diff HEAD
                    ;;
                working-tree)
                    git -C "$repository_root" diff --no-ext-diff
                    git -C "$repository_root" diff --cached --no-ext-diff
                    ;;
                staged)
                    git -C "$repository_root" diff --cached --no-ext-diff
                    ;;
                *)
                    git -C "$repository_root" diff --no-ext-diff "$REVIEW_TARGET"
                    ;;
            esac
        fi
    })"

    if corpus_matches 'rxjs|Observable|Subject|BehaviorSubject|\.pipe\(|\.subscribe\(|switchMap|concatMap|mergeMap|exhaustMap|catchError|toSignal|toObservable|takeUntilDestroyed|firstValueFrom|Promise|async|await|valueChanges'; then
        append_unique stack_instructions "$AI_ROOT/guidelines/stacks/angular-review/rxjs.md"
    fi
    if corpus_matches '@angular/forms|<form|ngSubmit|form\.|formControl|formGroup|\.valid|\.invalid|\.errors|required|AbstractControl|FormGroup|FormControl|FormArray|FormBuilder|NonNullableFormBuilder|Validators|ValidatorFn|AsyncValidatorFn|ControlValueAccessor|NG_VALUE_ACCESSOR|ReactiveFormsModule|getRawValue|FormsModule|ngModel|valueChanges'; then
        append_unique stack_instructions "$AI_ROOT/guidelines/stacks/angular-review/forms.md"
    fi
    if corpus_matches '\.routes\.ts|@angular/router|Routes|Router|RouterModule|provideRouter|ActivatedRoute|RouterLink|RouterOutlet|ResolveFn|CanActivate|CanMatch|withComponentInputBinding|paramMap|queryParams|toObservable'; then
        append_unique stack_instructions "$AI_ROOT/guidelines/stacks/angular-review/routing.md"
    fi
    if corpus_matches '\.html|kendo-|kendoButton|KENDO_|@progress/kendo-|@ardis/ngx-kendo-ui|DialogService|DialogRef|DialogContentBase|\.k-|::ng-deep|!important|<table|<select|<input|<textarea|<button|<a[[:space:]]|<form|<label'; then
        append_unique stack_instructions "$AI_ROOT/guidelines/stacks/angular-review/ui-kendo.md"
    fi
    if corpus_matches '\.(html|scss|sass|less|css)|templateUrl|styleUrl|template:|styles:|style="|class="'; then
        append_unique stack_instructions "$AI_ROOT/guidelines/stacks/angular-review/templates-styling.md"
    fi
}

collect_job_instruction_paths() {
    local stack

    if [[ "$MODE" == "handoff" && "$station" != "unresolved" ]]; then
        append_unique routed_instructions "$AI_ROOT/guidelines/handoff/common.md"
        case "$station" in
            hades | masterchief)
                append_unique routed_instructions "$AI_ROOT/guidelines/handoff/$station.md"
                ;;
        esac
    fi

    [[ -n "$repository_root" ]] && append_unique provisional_instructions "$AI_ROOT/guidelines/provisional/general.md"

    for stack in "${stacks[@]}"; do
        case "$stack:$MODE" in
            angular:development)
                append_unique stack_instructions "$AI_ROOT/guidelines/stacks/angular-development.md"
                append_unique provisional_instructions "$AI_ROOT/guidelines/provisional/angular.md"
                ;;
            angular:review)
                append_unique stack_instructions "$AI_ROOT/guidelines/stacks/angular-review/_core.md"
                select_angular_review_topics
                append_unique provisional_instructions "$AI_ROOT/guidelines/provisional/angular.md"
                ;;
            dotnet:*)
                append_unique stack_instructions "$AI_ROOT/guidelines/stacks/dotnet.md"
                append_unique provisional_instructions "$AI_ROOT/guidelines/provisional/dotnet.md"
                ;;
            sql:*)
                append_unique stack_instructions "$AI_ROOT/guidelines/stacks/sql.md"
                append_unique provisional_instructions "$AI_ROOT/guidelines/provisional/sql.md"
                ;;
            ops:*)
                append_unique stack_instructions "$AI_ROOT/guidelines/stacks/ops.md"
                ;;
        esac
    done

    for stack in "${routed_instructions[@]}"; do
        append_unique next_instructions "$stack"
    done
    for stack in "${stack_instructions[@]}"; do
        append_unique next_instructions "$stack"
    done
    for stack in "${project_instructions[@]}"; do
        append_unique next_instructions "$stack"
    done
    for stack in "${provisional_instructions[@]}"; do
        append_unique next_instructions "$stack"
    done
}

print_list() {
    local label="$1"
    shift

    printf '%s_BEGIN\n' "$label"
    if (($# == 0)); then
        printf 'none\n'
    else
        printf '%s\n' "$@"
    fi
    printf '%s_END\n' "$label"
}

while (($# > 0)); do
    case "$1" in
        --mode)
            (($# >= 2)) || die "--mode requires a value"
            MODE="$2"
            shift 2
            ;;
        --repository)
            (($# >= 2)) || die "--repository requires a path"
            REPOSITORY_INPUT="$2"
            shift 2
            ;;
        --target)
            (($# >= 2)) || die "--target requires a path"
            TARGET_INPUTS+=("$2")
            shift 2
            ;;
        --review-target)
            (($# >= 2)) || die "--review-target requires a value"
            REVIEW_TARGET="$2"
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

case "$MODE" in
    development | review | handoff) ;;
    *) die "--mode must be development, review, or handoff" ;;
esac

require_command git
require_command jq
[[ -f "$STATIONS_FILE" ]] || die "station inventory is missing: $STATIONS_FILE"

repository_root="$(discover_repository_root)"
if [[ -n "$repository_root" ]]; then
    repository_root="$(canonical_directory "$repository_root")"
fi

collect_review_targets

for target_input in "${TARGET_INPUTS[@]}"; do
    append_unique resolved_targets "$(resolve_target_path "$target_input")"
done

hostname_value="$(normalize_hostname "$(hostname -s 2>/dev/null || hostname)")"
station="$(discover_station "$hostname_value")"
[[ -n "$station" ]] || station="unresolved"

scope_path="${repository_root:-$(pwd -P)}"
if ((${#resolved_targets[@]} > 0)); then
    scope_path="${resolved_targets[0]}"
fi
universe="$(discover_universe "$station" "$scope_path")"

classify_stacks
collect_project_instructions
collect_job_instruction_paths

append_unique base_instructions "$AI_ROOT/identities.md"
append_unique base_instructions "$AI_ROOT/guidelines/guidelines.md"
while IFS= read -r always_source; do
    append_unique base_instructions "$always_source"
done < <(find "$AI_ROOT/guidelines/always" -maxdepth 1 -type f -name '*.md' -print | LC_ALL=C sort)

printf '===== RESOLVED CONTEXT =====\n'
printf 'status=%s\n' "$([[ "$station" != "unresolved" && "$universe" != "unresolved" && -n "$repository_root" ]] && printf resolved || printf partial)"
printf 'station=%s\n' "$station"
printf 'universe=%s\n' "$universe"
printf 'repository=%s\n' "${repository_root:-unresolved}"
printf 'mode=%s\n' "$MODE"
if ((${#stacks[@]} == 0)); then
    printf 'stacks=none\n'
else
    printf 'stacks=%s\n' "$(IFS=,; printf '%s' "${stacks[*]}")"
fi
print_list BASE_INSTRUCTION_PATHS "${base_instructions[@]}"
print_list TARGET_PATHS "${resolved_targets[@]}"
print_list ROUTED_INSTRUCTION_PATHS "${routed_instructions[@]}"
print_list STACK_INSTRUCTION_PATHS "${stack_instructions[@]}"
print_list PROJECT_INSTRUCTION_PATHS "${project_instructions[@]}"
print_list PROVISIONAL_INSTRUCTION_PATHS "${provisional_instructions[@]}"
print_list NEXT_INSTRUCTION_PATHS "${next_instructions[@]}"
