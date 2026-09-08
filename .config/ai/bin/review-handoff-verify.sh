#!/usr/bin/env bash

set -euo pipefail

failures=0

fail() {
    printf 'FAIL  %s\n' "$1"
    failures=$((failures + 1))
}

pass() {
    printf 'PASS  %s\n' "$1"
}

field() {
    local file="$1"
    local name="$2"

    sed -n "s/^- ${name}: //p" "$file" | head -n 1
}

validate_file() {
    local file="$1"

    if [[ -L "$file" || ! -f "$file" ]]; then
        fail "transporter is not a regular file: $file"
        return 1
    fi
    if [[ "$(stat -c '%a' "$file")" != "600" ]]; then
        fail "transporter mode is not 600: $file"
    fi
}

usage() {
    printf 'Usage: review-handoff-verify.sh <work|raynor|zeratul>\n'
}

lane="${1:-}"
[[ -z "${2:-}" ]] || {
    usage >&2
    exit 2
}

case "$lane" in
    work | raynor | zeratul) ;;
    *)
        usage >&2
        exit 2
        ;;
esac

handoff_directory="/home/oliver/$lane/.ai/review-handoff"
ai_directory="/home/oliver/$lane/.ai"
lane_root="/home/oliver/$lane"
request="$handoff_directory/request.md"
findings="$handoff_directory/findings.md"

if [[ -L "$ai_directory" || ! -d "$ai_directory" ]]; then
    fail "AI state root is not a physical directory: $ai_directory"
elif [[ "$(stat -c '%a' "$ai_directory")" != "700" ]]; then
    fail "AI state root mode is not 700: $ai_directory"
fi

if [[ -L "$handoff_directory" || ! -d "$handoff_directory" ]]; then
    fail "handoff lane is not a physical directory: $handoff_directory"
else
    [[ "$(stat -c '%a' "$handoff_directory")" == "700" ]] \
        && pass "handoff lane mode: $lane" \
        || fail "handoff lane mode is not 700: $handoff_directory"
fi

if [[ ! -e "$request" && ! -e "$findings" ]]; then
    pass "handoff lane is empty: $lane"
elif [[ ! -e "$request" ]]; then
    validate_file "$findings" || true
    fail "findings exist without a request: $lane"
else
    validate_file "$request" || true

    request_status="$(field "$request" Status)"
    request_station="$(field "$request" Station)"
    request_lane="$(field "$request" Lane)"
    request_id="$(field "$request" 'Handoff ID')"
    request_created="$(field "$request" Created)"
    request_repository="$(field "$request" Repository)"

    [[ "$request_status" == "ready-for-review" ]] \
        || fail "request status is not ready-for-review: ${request_status:-missing}"
    [[ "$request_station" == "masterchief" ]] \
        || fail "request station is not masterchief: ${request_station:-missing}"
    [[ "$request_lane" == "$lane" ]] \
        || fail "request lane is ${request_lane:-missing}; expected $lane"
    if [[ "$request_repository" == "$lane_root/"* \
        && "$(git -C "$request_repository" rev-parse --show-toplevel 2>/dev/null || true)" == "$request_repository" ]]; then
        repository_name="$(basename "$request_repository")"
    else
        repository_name=""
        fail "request repository is not a canonical Git root inside $lane_root"
    fi
    [[ -n "$repository_name" && "$request_id" == "$lane:$repository_name:"* ]] \
        || fail "request handoff ID does not match its lane and repository"
    date -d "$request_created" +%s >/dev/null 2>&1 \
        || fail "request Created timestamp is missing or invalid"

    if [[ "$lane" == "work" ]]; then
        coworker="$(field "$request" Coworker)"
        reviewer="$(field "$request" Reviewer)"
        case "$coworker" in Artanis | Argus | Aegis) ;; *) fail "invalid Work coworker: ${coworker:-missing}" ;; esac
        case "$reviewer" in Artanis | Argus | Aegis) ;; *) fail "invalid Work reviewer: ${reviewer:-missing}" ;; esac
        [[ -z "$coworker" || -z "$reviewer" || "$coworker" != "$reviewer" ]] \
            || fail "Work coworker and reviewer must differ"
    fi

    if [[ ! -e "$findings" ]]; then
        pass "handoff request awaits review: $lane"
    else
        validate_file "$findings" || true

        findings_status="$(field "$findings" Status)"
        findings_station="$(field "$findings" Station)"
        findings_lane="$(field "$findings" Lane)"
        findings_id="$(field "$findings" 'Handoff ID')"
        findings_reviewed="$(field "$findings" Reviewed)"

        [[ "$findings_status" == "review-complete" ]] \
            || fail "findings status is not review-complete: ${findings_status:-missing}"
        [[ "$findings_station" == "masterchief" ]] \
            || fail "findings station is not masterchief: ${findings_station:-missing}"
        [[ "$findings_lane" == "$lane" ]] \
            || fail "findings lane is ${findings_lane:-missing}; expected $lane"
        date -d "$findings_reviewed" +%s >/dev/null 2>&1 \
            || fail "findings Reviewed timestamp is missing or invalid"

        if [[ "$request_id" == "$findings_id" ]]; then
            pair_failures_before="$failures"
            for name in Repository Branch 'Review target'; do
                request_value="$(field "$request" "$name")"
                findings_value="$(field "$findings" "$name")"
                [[ -n "$request_value" \
                    && ("$request_value" == "$findings_value" \
                        || "$findings_value" == "$request_value "*) ]] \
                    || fail "$name differs for handoff $request_id"
            done
            if [[ "$lane" == "work" ]]; then
                [[ "$(field "$findings" Coworker)" == "$coworker" ]] \
                    || fail "Work coworker differs between request and findings"
                [[ "$(field "$findings" Reviewer)" == "$reviewer" ]] \
                    || fail "Work reviewer differs between request and findings"
            fi
            if [[ "$failures" == "$pair_failures_before" ]]; then
                pass "handoff request and findings are paired: $lane"
            fi
        elif request_epoch="$(date -d "$request_created" +%s 2>/dev/null)" \
            && findings_epoch="$(date -d "$findings_reviewed" +%s 2>/dev/null)" \
            && ((request_epoch > findings_epoch)); then
            pass "new handoff request awaits review: $lane"
        else
            fail "findings have a different ID and are not older than the request: $lane"
        fi
    fi
fi

if ((failures > 0)); then
    printf '\nSummary: %d failure(s)\n' "$failures"
    exit 1
fi

printf '\nSummary: valid\n'
