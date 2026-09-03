#!/usr/bin/env bash

set -eo pipefail

LIMIT_BYTES=22528
BATCH_ID=""
EXPECTED_FILES=""
EXPECTED_BYTES=""
instruction_paths=()

usage() {
    cat <<'EOF'
Read one ordered instruction batch with completeness markers.

Usage:
  ai-read-instructions.sh --batch <id> --expected-files <count> \
    --expected-bytes <count> -- <absolute-path>...

Run the exact INSTRUCTION_BATCH_N_COMMAND emitted by ai-context.sh.
EOF
}

die() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

positive_integer() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

nonnegative_integer() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

file_size_bytes() {
    wc -c < "$1" | tr -d '[:space:]'
}

while (($# > 0)); do
    case "$1" in
        --batch)
            (($# >= 2)) || die "--batch requires a value"
            BATCH_ID="$2"
            shift 2
            ;;
        --expected-files)
            (($# >= 2)) || die "--expected-files requires a value"
            EXPECTED_FILES="$2"
            shift 2
            ;;
        --expected-bytes)
            (($# >= 2)) || die "--expected-bytes requires a value"
            EXPECTED_BYTES="$2"
            shift 2
            ;;
        --)
            shift
            while (($# > 0)); do
                instruction_paths[${#instruction_paths[@]}]="$1"
                shift
            done
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *) die "unknown argument: $1" ;;
    esac
done

positive_integer "$BATCH_ID" || die "--batch must be a positive integer"
positive_integer "$EXPECTED_FILES" || die "--expected-files must be a positive integer"
nonnegative_integer "$EXPECTED_BYTES" || die "--expected-bytes must be a non-negative integer"
((${#instruction_paths[@]} == EXPECTED_FILES)) \
    || die "batch $BATCH_ID expected $EXPECTED_FILES files but received ${#instruction_paths[@]}"

actual_bytes=0
for path in "${instruction_paths[@]}"; do
    [[ "$path" == /* ]] || die "instruction path must be absolute: $path"
    [[ "$path" != *$'\n'* ]] || die "instruction path contains a newline"
    [[ -f "$path" ]] || die "instruction source is missing: $path"
    [[ -r "$path" ]] || die "instruction source is unreadable: $path"
    actual_bytes=$((actual_bytes + $(file_size_bytes "$path")))
done

((actual_bytes == EXPECTED_BYTES)) \
    || die "batch $BATCH_ID content changed after routing: expected $EXPECTED_BYTES bytes, found $actual_bytes"
if ((actual_bytes > LIMIT_BYTES && EXPECTED_FILES > 1)); then
    die "batch $BATCH_ID exceeds the $LIMIT_BYTES-byte limit"
fi

printf '===== INSTRUCTION_BATCH_BEGIN id=%s files=%s bytes=%s =====\n' \
    "$BATCH_ID" "$EXPECTED_FILES" "$actual_bytes"
file_index=0
for path in "${instruction_paths[@]}"; do
    file_index=$((file_index + 1))
    file_bytes="$(file_size_bytes "$path")"
    printf '===== INSTRUCTION_FILE_BEGIN index=%s bytes=%s path=%s =====\n' \
        "$file_index" "$file_bytes" "$path"
    cat "$path"
    printf '\n===== INSTRUCTION_FILE_END index=%s bytes=%s path=%s =====\n' \
        "$file_index" "$file_bytes" "$path"
done
printf '===== INSTRUCTION_BATCH_COMPLETE id=%s files=%s bytes=%s =====\n' \
    "$BATCH_ID" "$EXPECTED_FILES" "$actual_bytes"
