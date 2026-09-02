#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AI_SOURCE="$FORGE_ROOT/.config/ai"
USER_CONFIG_ROOT="${AI_CONFIG_USER_ROOT:-$HOME}"
AI_LINK="$USER_CONFIG_ROOT/.config/ai"
CODEX_DIR="$USER_CONFIG_ROOT/.codex"
CLAUDE_DIR="$USER_CONFIG_ROOT/.claude"
CODEX_BOOTSTRAP="$CODEX_DIR/AGENTS.md"
CLAUDE_BOOTSTRAP="$CLAUDE_DIR/CLAUDE.md"
CODEX_TEMPLATE="$AI_SOURCE/bootstrap/codex-AGENTS.md"
CLAUDE_TEMPLATE="$AI_SOURCE/bootstrap/claude-CLAUDE.md"
REQUIRED_SOURCES=(
    identities.md
    guidelines/guidelines.md
    guidelines/always/review-handoff.md
    guidelines/always/test-execution.md
    guidelines/handoff/common.md
    guidelines/handoff/hades.md
    guidelines/handoff/masterchief.md
    guidelines/stacks/angular-development.md
    guidelines/stacks/angular-review/_core.md
    guidelines/stacks/angular-review/forms.md
    guidelines/stacks/angular-review/routing.md
    guidelines/stacks/angular-review/rxjs.md
    guidelines/stacks/angular-review/templates-styling.md
    guidelines/stacks/angular-review/ui-kendo.md
    guidelines/stacks/docker-db-local-fallback.md
    guidelines/stacks/dotnet.md
    guidelines/stacks/ops.md
    guidelines/stacks/sql.md
    bootstrap/codex-AGENTS.md
    bootstrap/claude-CLAUDE.md
)
failures=0
warnings=0

usage() {
    cat <<'EOF'
Manage the shared Mac Forge AI instruction configuration.

Usage:
  ai-config.sh verify
  ai-config.sh install
  ai-config.sh sync

Commands:
  verify  Read-only validation of the shared symlink, bootstrap files, station
          routing, agent-universe context, and local Git state.
  install Back up conflicting local paths, install the shared symlink and
          canonical Codex/Claude bootstrap files, then verify the result.
          Complete ~/.codex and ~/.claude directories are never replaced.
  sync    Refuse a dirty Mac Forge checkout, pull with --ff-only, install the
          shared symlink and canonical bootstrap files, then verify.
EOF
}

pass() {
    printf 'PASS  %s\n' "$1"
}

info() {
    printf 'INFO  %s\n' "$1"
}

warn() {
    printf 'WARN  %s\n' "$1"
    warnings=$((warnings + 1))
}

fail() {
    printf 'FAIL  %s\n' "$1"
    failures=$((failures + 1))
}

die() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

physical_directory() {
    cd -P "$1" 2>/dev/null && pwd
}

detect_station() {
    local hostname_value

    hostname_value="$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)"
    hostname_value="${hostname_value%%.*}"
    printf '%s\n' "$hostname_value" | tr '[:upper:]' '[:lower:]'
}

check_required_sources() {
    local relative_path

    for relative_path in "${REQUIRED_SOURCES[@]}"; do
        if [[ -f "$AI_SOURCE/$relative_path" && ! -L "$AI_SOURCE/$relative_path" ]]; then
            pass "shared source: $relative_path"
        else
            fail "shared source missing or not a regular file: $relative_path"
        fi
    done
}

require_source_layout() {
    local relative_path

    for relative_path in "${REQUIRED_SOURCES[@]}"; do
        [[ -f "$AI_SOURCE/$relative_path" && ! -L "$AI_SOURCE/$relative_path" ]] \
            || die "shared source missing or not a regular file: $AI_SOURCE/$relative_path"
    done
}

check_ai_link() {
    local actual_source expected_source

    if [[ ! -L "$AI_LINK" ]]; then
        fail "$AI_LINK is not a symlink"
        return
    fi

    if ! actual_source="$(physical_directory "$AI_LINK")"; then
        fail "$AI_LINK is a dangling or unreadable symlink"
        return
    fi
    expected_source="$(physical_directory "$AI_SOURCE")"

    if [[ "$actual_source" == "$expected_source" ]]; then
        pass "$AI_LINK resolves to $expected_source"
    else
        fail "$AI_LINK resolves to $actual_source; expected $expected_source"
    fi
}

check_tool_directory() {
    local directory_path="$1"
    local tool_name="$2"

    if [[ -L "$directory_path" ]]; then
        fail "$tool_name directory must remain physical: $directory_path"
    elif [[ -d "$directory_path" ]]; then
        pass "$tool_name directory is physical: $directory_path"
    else
        fail "$tool_name directory is missing: $directory_path"
    fi
}

check_bootstrap() {
    local source_path="$1"
    local target_path="$2"
    local tool_name="$3"

    if [[ -L "$target_path" ]]; then
        fail "$tool_name bootstrap must be a regular file: $target_path"
    elif [[ ! -f "$target_path" ]]; then
        fail "$tool_name bootstrap is missing: $target_path"
    elif cmp -s "$source_path" "$target_path"; then
        pass "$tool_name bootstrap matches the shared template"
    else
        fail "$tool_name bootstrap differs from $source_path"
    fi
}

check_git_state() {
    local branch head status_output upstream counts ahead behind

    if ! git -C "$FORGE_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        fail "Mac Forge is not a Git worktree: $FORGE_ROOT"
        return
    fi

    head="$(git -C "$FORGE_ROOT" rev-parse --short=12 HEAD)"
    branch="$(git -C "$FORGE_ROOT" symbolic-ref --short -q HEAD || true)"
    pass "Mac Forge revision: ${branch:-detached}@$head"

    status_output="$(git -C "$FORGE_ROOT" status --porcelain)"
    if [[ -z "$status_output" ]]; then
        pass "Mac Forge working tree is clean"
    else
        warn "Mac Forge working tree is dirty; ai-config sync will refuse to pull"
    fi

    if upstream="$(git -C "$FORGE_ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)"; then
        counts="$(git -C "$FORGE_ROOT" rev-list --left-right --count "HEAD...$upstream")"
        read -r ahead behind <<< "$counts"
        if [[ "$ahead" == "0" && "$behind" == "0" ]]; then
            pass "Mac Forge matches cached upstream $upstream"
        else
            warn "Mac Forge differs from cached upstream $upstream: ahead $ahead, behind $behind"
        fi
    else
        warn "Mac Forge branch has no configured upstream"
    fi
}

check_masterchief_context() {
    local identity="${FORGE_AGENT_IDENTITY:-}"
    local universe_root="${FORGE_UNIVERSE_ROOT:-}"
    local work_root="${FORGE_WORK_ROOT:-}"
    local expected_root current_path

    if [[ -z "$identity" && -z "$universe_root" ]]; then
        if [[ -z "$work_root" || "$work_root" == "$HOME/work" ]]; then
            info "normal MasterChief shell; no agent-universe context is active"
        else
            fail "unexpected MasterChief work root outside an agent context: $work_root"
        fi
        return
    fi

    if [[ -z "$identity" || -z "$universe_root" ]]; then
        fail "incomplete MasterChief agent-universe context"
        return
    fi

    case "$identity" in
        raynor) expected_root="/home/oliver/raynor" ;;
        zeratul) expected_root="/home/oliver/zeratul" ;;
        *)
            fail "invalid MasterChief agent identity: ${identity:-unset}"
            return
            ;;
    esac

    if [[ "$universe_root" == "$expected_root" ]]; then
        pass "$identity universe root: $universe_root"
    else
        fail "$identity universe root is ${universe_root:-unset}; expected $expected_root"
    fi

    if [[ "$work_root" == "$expected_root" ]]; then
        pass "$identity work root: $work_root"
    else
        fail "$identity work root is ${work_root:-unset}; expected $expected_root"
    fi

    current_path="$(pwd -P)"
    case "$current_path" in
        "$expected_root" | "$expected_root"/*)
            pass "$identity shell remains inside its universe"
            ;;
        *)
            fail "$identity shell is outside its universe: $current_path"
            ;;
    esac
}

check_station_context() {
    local station

    station="$(detect_station)"
    case "$station" in
        hades)
            pass "station route: hades"
            if [[ -n "${FORGE_AGENT_IDENTITY:-}${FORGE_UNIVERSE_ROOT:-}${FORGE_WORK_ROOT:-}" ]]; then
                fail "MasterChief agent-universe variables must not be active on Hades"
            else
                pass "Hades has no MasterChief agent-universe context"
            fi
            ;;
        masterchief)
            pass "station route: masterchief"
            check_masterchief_context
            ;;
        *)
            fail "unsupported station hostname: ${station:-unknown}"
            ;;
    esac
}

verify_config() {
    failures=0
    warnings=0

    printf 'AI configuration verification\n\n'
    check_required_sources
    check_ai_link
    check_tool_directory "$CODEX_DIR" "Codex"
    check_tool_directory "$CLAUDE_DIR" "Claude"
    check_bootstrap "$CODEX_TEMPLATE" "$CODEX_BOOTSTRAP" "Codex"
    check_bootstrap "$CLAUDE_TEMPLATE" "$CLAUDE_BOOTSTRAP" "Claude"
    check_station_context
    check_git_state

    printf '\nSummary: %d failure(s), %d warning(s)\n' "$failures" "$warnings"
    [[ "$failures" -eq 0 ]]
}

next_backup_path() {
    local target_path="$1"
    local timestamp candidate suffix

    timestamp="$(date +%Y%m%d-%H%M%S)"
    candidate="${target_path}.pre-ai-config-${timestamp}"
    suffix=1
    while [[ -e "$candidate" || -L "$candidate" ]]; do
        candidate="${target_path}.pre-ai-config-${timestamp}-${suffix}"
        suffix=$((suffix + 1))
    done
    printf '%s\n' "$candidate"
}

backup_existing() {
    local target_path="$1"
    local backup_path

    backup_path="$(next_backup_path "$target_path")"
    mv "$target_path" "$backup_path"
    printf 'Backed up: %s -> %s\n' "$target_path" "$backup_path"
}

ensure_tool_directory() {
    local directory_path="$1"
    local tool_name="$2"

    if [[ -L "$directory_path" ]]; then
        die "$tool_name directory is a symlink; refusing to replace it: $directory_path"
    fi
    if [[ -e "$directory_path" && ! -d "$directory_path" ]]; then
        die "$tool_name path is not a directory; refusing to replace it: $directory_path"
    fi
    mkdir -p "$directory_path"
}

install_ai_link() {
    local actual_source expected_source

    mkdir -p "$USER_CONFIG_ROOT/.config"
    expected_source="$(physical_directory "$AI_SOURCE")"

    if [[ -L "$AI_LINK" ]] && actual_source="$(physical_directory "$AI_LINK")" \
        && [[ "$actual_source" == "$expected_source" ]]; then
        printf 'Already linked: %s -> %s\n' "$AI_LINK" "$expected_source"
        return
    fi

    if [[ -e "$AI_LINK" || -L "$AI_LINK" ]]; then
        backup_existing "$AI_LINK"
    fi

    ln -s "$expected_source" "$AI_LINK"
    printf 'Linked: %s -> %s\n' "$AI_LINK" "$expected_source"
}

install_bootstrap() {
    local source_path="$1"
    local target_path="$2"

    if [[ -f "$target_path" && ! -L "$target_path" ]] && cmp -s "$source_path" "$target_path"; then
        printf 'Already current: %s\n' "$target_path"
        return
    fi

    if [[ -e "$target_path" || -L "$target_path" ]]; then
        backup_existing "$target_path"
    fi

    install -m 644 "$source_path" "$target_path"
    printf 'Installed: %s\n' "$target_path"
}

install_config() {
    [[ -d "$AI_SOURCE" ]] || die "shared AI source is missing: $AI_SOURCE"
    require_source_layout

    ensure_tool_directory "$CODEX_DIR" "Codex"
    ensure_tool_directory "$CLAUDE_DIR" "Claude"
    install_ai_link
    install_bootstrap "$CODEX_TEMPLATE" "$CODEX_BOOTSTRAP"
    install_bootstrap "$CLAUDE_TEMPLATE" "$CLAUDE_BOOTSTRAP"

    printf '\n'
    verify_config
}

sync_config() {
    local status_output upstream

    git -C "$FORGE_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
        || die "Mac Forge is not a Git worktree: $FORGE_ROOT"

    status_output="$(git -C "$FORGE_ROOT" status --porcelain)"
    [[ -z "$status_output" ]] \
        || die "Mac Forge has local changes; commit, discard, or move them before syncing"

    upstream="$(git -C "$FORGE_ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)" \
        || die "the current Mac Forge branch has no configured upstream"

    printf 'Syncing Mac Forge from %s with fast-forward only...\n' "$upstream"
    git -C "$FORGE_ROOT" pull --ff-only
    printf '\n'
    install_config
    printf '\nStart new Codex and Claude sessions after instruction changes.\n'
}

case "${1:-}" in
    "" | -h | --help | help)
        usage
        ;;
    verify)
        [[ "$#" -eq 1 ]] || die "verify accepts no additional arguments"
        verify_config
        ;;
    install)
        [[ "$#" -eq 1 ]] || die "install accepts no additional arguments"
        install_config
        ;;
    sync)
        [[ "$#" -eq 1 ]] || die "sync accepts no additional arguments"
        sync_config
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
