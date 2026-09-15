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

identity_from_slug() {
    case "$1" in
        artanis) printf 'Artanis' ;;
        karax) printf 'Karax' ;;
        argus) printf 'Argus' ;;
        aegis) printf 'Aegis' ;;
        *) return 1 ;;
    esac
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

validate_pair() {
    local request="$1"
    local findings="$2"
    local expected_identity="$3"
    local slug="$4"
    local request_status request_station request_lane request_id request_created
    local request_repository coworker repository_name reviewer
    local findings_status findings_station findings_lane findings_id findings_reviewed
    local pair_failures_before request_epoch findings_epoch name
    local request_value findings_value

    if [[ ! -e "$request" && ! -e "$findings" ]]; then
        return 0
    fi
    if [[ ! -e "$request" ]]; then
        validate_file "$findings" || true
        fail "findings exist without a request: $lane $slug"
        return 0
    fi

    validate_file "$request" || true

    request_status="$(field "$request" Status)"
    request_station="$(field "$request" Station)"
    request_lane="$(field "$request" Lane)"
    request_id="$(field "$request" 'Handoff ID')"
    request_created="$(field "$request" Created)"
    request_repository="$(field "$request" Repository)"
    coworker="$(field "$request" Coworker)"

    [[ "$request_status" == "ready-for-review" ]] \
        || fail "request status is not ready-for-review: ${request_status:-missing} ($slug)"
    [[ "$request_station" == "masterchief" ]] \
        || fail "request station is not masterchief: ${request_station:-missing} ($slug)"
    [[ "$request_lane" == "$lane" ]] \
        || fail "request lane is ${request_lane:-missing}; expected $lane ($slug)"
    if [[ "$request_repository" == "$lane_root/"* \
        && "$(git -C "$request_repository" rev-parse --show-toplevel 2>/dev/null || true)" == "$request_repository" ]]; then
        repository_name="$(basename "$request_repository")"
    else
        repository_name=""
        fail "request repository is not a canonical Git root inside $lane_root ($slug)"
    fi
    if [[ "$(basename "$request")" != "request.md" ]]; then
        [[ "$coworker" == "$expected_identity" ]] \
            || fail "request coworker is ${coworker:-missing}; expected $expected_identity ($slug)"
    elif [[ -n "$coworker" && "$coworker" != "$expected_identity" ]]; then
        fail "legacy request coworker is $coworker; expected $expected_identity"
    fi
    if [[ "$(basename "$request")" == "request.md" ]]; then
        [[ -n "$repository_name" && "$request_id" == "$lane:$repository_name:"* ]] \
            || fail "legacy request handoff ID does not match its lane and repository ($slug)"
    else
        [[ -n "$repository_name" && "$request_id" == "$lane:$repository_name:$slug:"* ]] \
            || fail "request handoff ID does not match its lane, repository, and coworker ($slug)"
    fi
    date -d "$request_created" +%s >/dev/null 2>&1 \
        || fail "request Created timestamp is missing or invalid ($slug)"

    if [[ "$lane" == "work" ]]; then
        reviewer="$(field "$request" Reviewer)"
        case "$coworker" in Artanis | Karax | Argus | Aegis) ;; *) fail "invalid Work coworker: ${coworker:-missing}" ;; esac
        case "$reviewer" in Artanis | Karax | Argus | Aegis) ;; *) fail "invalid Work reviewer: ${reviewer:-missing}" ;; esac
        [[ -z "$coworker" || -z "$reviewer" || "$coworker" != "$reviewer" ]] \
            || fail "Work coworker and reviewer must differ ($slug)"
    else
        case "$coworker" in Artanis | Karax) ;; *) fail "invalid coworker: ${coworker:-missing}" ;; esac
    fi

    if [[ ! -e "$findings" ]]; then
        pass "handoff request awaits review: $lane $slug"
        return 0
    fi

    validate_file "$findings" || true

    findings_status="$(field "$findings" Status)"
    findings_station="$(field "$findings" Station)"
    findings_lane="$(field "$findings" Lane)"
    findings_id="$(field "$findings" 'Handoff ID')"
    findings_reviewed="$(field "$findings" Reviewed)"

    [[ "$findings_status" == "review-complete" ]] \
        || fail "findings status is not review-complete: ${findings_status:-missing} ($slug)"
    [[ "$findings_station" == "masterchief" ]] \
        || fail "findings station is not masterchief: ${findings_station:-missing} ($slug)"
    [[ "$findings_lane" == "$lane" ]] \
        || fail "findings lane is ${findings_lane:-missing}; expected $lane ($slug)"
    date -d "$findings_reviewed" +%s >/dev/null 2>&1 \
        || fail "findings Reviewed timestamp is missing or invalid ($slug)"

    if [[ "$request_id" == "$findings_id" ]]; then
        pair_failures_before="$failures"
        for name in Repository Branch 'Review target' Coworker; do
            request_value="$(field "$request" "$name")"
            findings_value="$(field "$findings" "$name")"
            [[ -n "$request_value" \
                && ("$request_value" == "$findings_value" \
                    || "$findings_value" == "$request_value "*) ]] \
                || fail "$name differs for handoff $request_id ($slug)"
        done
        if [[ "$lane" == "work" ]]; then
            [[ "$(field "$findings" Reviewer)" == "$reviewer" ]] \
                || fail "Work reviewer differs between request and findings ($slug)"
        fi
        if [[ "$failures" == "$pair_failures_before" ]]; then
            pass "handoff request and findings are paired: $lane $slug"
        fi
    elif request_epoch="$(date -d "$request_created" +%s 2>/dev/null)" \
        && findings_epoch="$(date -d "$findings_reviewed" +%s 2>/dev/null)" \
        && ((request_epoch > findings_epoch)); then
        pass "new handoff request awaits review: $lane $slug"
    else
        fail "findings have a different ID and are not older than the request: $lane $slug"
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

if [[ "$lane" == "work" ]]; then
    slugs=(artanis karax argus aegis)
else
    slugs=(artanis karax)
fi

slots_found=0
for slug in "${slugs[@]}"; do
    request="$handoff_directory/request-$slug.md"
    findings="$handoff_directory/findings-$slug.md"
    if [[ -e "$request" || -e "$findings" ]]; then
        slots_found=$((slots_found + 1))
        validate_pair "$request" "$findings" "$(identity_from_slug "$slug")" "$slug"
    fi
done

legacy_request="$handoff_directory/request.md"
legacy_findings="$handoff_directory/findings.md"
if [[ -e "$legacy_request" || -e "$legacy_findings" ]]; then
    if [[ -e "$handoff_directory/request-artanis.md" || -e "$handoff_directory/findings-artanis.md" ]]; then
        fail "legacy unnamed transporter files must not coexist with Artanis named files: $lane"
    else
        slots_found=$((slots_found + 1))
        validate_pair "$legacy_request" "$legacy_findings" "Artanis" "artanis"
    fi
fi

if ((slots_found == 0)); then
    pass "handoff lane is empty: $lane"
fi

if ((failures > 0)); then
    printf '\nSummary: %d failure(s)\n' "$failures"
    exit 1
fi

printf '\nSummary: valid\n'
