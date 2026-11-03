#!/usr/bin/env bash

set -euo pipefail

die() {
    printf 'Error: %s\n' "$1" >&2
    exit 1
}

usage() {
    printf 'Usage: review-handoff-publish.sh /tmp/<source>.md <request|findings>-<coworker>.md\n'
}

field() {
    local file="$1"
    local name="$2"

    sed -n "s/^- ${name}: //p" "$file" | head -n 1
}

identity_from_slug() {
    case "$1" in
        artanis) printf 'Artanis' ;;
        argus) printf 'Argus' ;;
        aegis) printf 'Aegis' ;;
        aldaris) printf 'Aldaris' ;;
        *) return 1 ;;
    esac
}

physical_git_root() {
    local root

    root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
    (cd "$root" && pwd -P)
}

resolve_masterchief_lane() {
    local repository="$1"
    local lane_root lane

    case "$repository" in
        /home/oliver/work | /home/oliver/work/*)
            lane=work
            lane_root=/home/oliver/work
            [[ -z "${FORGE_UNIVERSE_ROOT:-}${FORGE_AGENT_IDENTITY:-}" \
                && ( -z "${FORGE_WORK_ROOT:-}" || "${FORGE_WORK_ROOT:-}" == "$lane_root" ) ]] \
                || die 'the Work lane conflicts with an active agent-universe context'
            ;;
        /home/oliver/raynor | /home/oliver/raynor/*)
            lane=raynor
            lane_root=/home/oliver/raynor
            if [[ -n "${FORGE_UNIVERSE_ROOT:-}${FORGE_AGENT_IDENTITY:-}" ]]; then
                [[ "${FORGE_UNIVERSE_ROOT:-}" == "$lane_root" \
                    && "${FORGE_WORK_ROOT:-}" == "$lane_root" \
                    && "${FORGE_AGENT_IDENTITY:-}" == "$lane" ]] \
                    || die 'the repository conflicts with the Raynor agent-universe context'
            fi
            ;;
        /home/oliver/zeratul | /home/oliver/zeratul/*)
            lane=zeratul
            lane_root=/home/oliver/zeratul
            if [[ -n "${FORGE_UNIVERSE_ROOT:-}${FORGE_AGENT_IDENTITY:-}" ]]; then
                [[ "${FORGE_UNIVERSE_ROOT:-}" == "$lane_root" \
                    && "${FORGE_WORK_ROOT:-}" == "$lane_root" \
                    && "${FORGE_AGENT_IDENTITY:-}" == "$lane" ]] \
                    || die 'the repository conflicts with the Zeratul agent-universe context'
            fi
            ;;
        *)
            die "the repository is outside a MasterChief handoff lane: $repository"
            ;;
    esac

    expected_station=masterchief
    expected_lane="$lane"
    handoff_directory="$lane_root/.ai/review-handoff"
    [[ ! -L "$lane_root/.ai" && -d "$lane_root/.ai" ]] \
        || die "the AI state root is not a physical directory: $lane_root/.ai"
    [[ ! -L "$handoff_directory" && -d "$handoff_directory" ]] \
        || die "the handoff lane is not a physical directory: $handoff_directory"
}

resolve_hades_lane() {
    local repository="$1"
    local project_key handoff_root

    [[ -z "${FORGE_UNIVERSE_ROOT:-}${FORGE_WORK_ROOT:-}${FORGE_AGENT_IDENTITY:-}" ]] \
        || die 'MasterChief agent-universe variables must not be active on Hades'
    project_key="$(basename "$repository")"
    [[ "$project_key" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] \
        || die "the repository basename is not a safe Hades project key: $project_key"

    expected_station=hades
    expected_lane="$project_key"
    handoff_root=/Users/oliver/handoffserver
    handoff_directory="$handoff_root/$project_key"
    [[ ! -L "$handoff_root" && -d "$handoff_root" ]] \
        || die "the Hades handoff root is not a physical directory: $handoff_root"
    [[ ! -L "$handoff_directory" && -d "$handoff_directory" ]] \
        || die "the Hades project lane is not a physical directory: $handoff_directory"
}

source_file="${1:-}"
transporter="${2:-}"
[[ -z "${3:-}" ]] || {
    usage >&2
    exit 2
}
[[ -n "$source_file" && -n "$transporter" ]] || {
    usage >&2
    exit 2
}

case "$source_file" in
    /tmp/*) ;;
    *) die 'the source must be an absolute path directly under /tmp' ;;
esac
[[ "${source_file#/tmp/}" != */* ]] \
    || die 'the source must be directly under /tmp'
[[ ! -L "$source_file" && -f "$source_file" && -O "$source_file" ]] \
    || die "the source is not an owned physical regular file: $source_file"
[[ -s "$source_file" ]] || die "the source is empty: $source_file"

if [[ "$transporter" =~ ^(request|findings)-(artanis|argus|aegis|aldaris)\.md$ ]]; then
    document_kind="${BASH_REMATCH[1]}"
    coworker_slug="${BASH_REMATCH[2]}"
else
    die "the transporter filename is invalid: $transporter"
fi

repository="$(physical_git_root)" \
    || die 'the current directory is not inside one canonical Git repository'
station="$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)"
station="$(printf '%s' "$station" | tr '[:upper:]' '[:lower:]')"

case "$station" in
    masterchief)
        [[ "$coworker_slug" != aldaris ]] \
            || die 'Aldaris transporter files are not supported in MasterChief lanes'
        resolve_masterchief_lane "$repository"
        ;;
    hades)
        resolve_hades_lane "$repository"
        ;;
    *)
        die "unsupported station: ${station:-unknown}"
        ;;
esac

expected_coworker="$(identity_from_slug "$coworker_slug")"
[[ "$(field "$source_file" Station)" == "$expected_station" ]] \
    || die "the source Station does not match $expected_station"
[[ "$(field "$source_file" Lane)" == "$expected_lane" ]] \
    || die "the source Lane does not match $expected_lane"
[[ "$(field "$source_file" Coworker)" == "$expected_coworker" ]] \
    || die "the source Coworker does not match $expected_coworker"

destination="$handoff_directory/$transporter"
[[ ! -L "$destination" ]] \
    || die "the destination is a symlink: $destination"
[[ ! -e "$destination" || -f "$destination" ]] \
    || die "the destination is not a regular file: $destination"

temporary_file="$(mktemp "$handoff_directory/.${document_kind}-${coworker_slug}.publish.XXXXXX")"
cleanup() {
    [[ -z "${temporary_file:-}" || ! -e "$temporary_file" ]] || rm -f "$temporary_file"
}
trap cleanup EXIT HUP INT TERM

umask 077
install -m 600 "$source_file" "$temporary_file"
mv -f "$temporary_file" "$destination"
temporary_file=''
printf 'Published: %s\n' "$destination"
