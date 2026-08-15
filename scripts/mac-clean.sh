#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

die() {
  echo "✗ $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: mac-clean [--full | --list]

Run the approved macOS cleanup scripts.

With no arguments (in an interactive terminal with fzf installed), mac-clean
opens a picker: choose "All" to run the standard cleanup, or select specific
segments with TAB and clean only those.

Options:
  --full      Run standard and full-only cleanup scripts (non-interactive).
  --list      Show all approved cleanup scripts and their classification.
  -v, --verbose  Stream each cleaner's full output live (default: quiet, with
                 output shown only when a cleaner fails).
  -h, --help  Show this help.

Each run ends with a summary of approximate space freed per segment and in
total. Freed sizes are measured as free-space deltas on the boot volume, so
they are approximate and can be skewed by concurrent disk activity.
EOF
}

# Free space (in 1 KiB blocks) on the boot volume.
free_kib() {
  df -Pk / | awk 'NR == 2 { print $4 }'
}

# Human-readable size from a KiB amount; negatives are clamped to zero.
format_kib() {
  awk -v k="$1" 'BEGIN {
    if (k < 0) k = 0
    if (k >= 1048576) printf "%.2f GiB", k / 1048576
    else if (k >= 1024) printf "%.1f MiB", k / 1024
    else printf "%d KiB", k
  }'
}

# Short label for the summary (text before the em dash in describe()).
short_label() {
  local desc
  desc="$(describe "$1")"
  printf '%s' "${desc%% — *}"
}

# Friendly, human-readable description for each cleaner (portable case; no bash 4 assoc arrays).
describe() {
  case "$1" in
    mac-clean-homebrew.sh)             echo "Homebrew — prune old formulae, downloads & cache" ;;
    mac-clean-browser-caches.sh)       echo "Browser caches — Chrome/Brave cache & code cache" ;;
    mac-clean-claude-cache.sh)         echo "Claude cache — staging/temp files" ;;
    mac-clean-codex-cache.sh)          echo "Codex cache — CLI staging/temp files" ;;
    mac-clean-copilot-index-cache.sh)  echo "Copilot index cache — project context & index" ;;
    mac-clean-docker-build-cache.sh)   echo "Docker build cache — old buildx layers" ;;
    mac-clean-nuget-transient.sh)      echo "NuGet transient — http-cache, scratch & plugin cache" ;;
    mac-clean-npm-cache.sh)            echo "npm cache — global download cache" ;;
    mac-clean-pip-cache.sh)            echo "pip cache — download & wheel cache" ;;
    mac-clean-rider-caches.sh)         echo "JetBrains Rider — caches, indexes & host temp" ;;
    mac-clean-yarn-cache.sh)           echo "Yarn cache — global package cache" ;;
    mac-clean-swiftpm-cache.sh)        echo "Swift Package Manager — package cache" ;;
    mac-clean-go-build-cache.sh)       echo "Go build cache — compiled build artifacts (GOCACHE)" ;;
    mac-clean-vscode-caches.sh)        echo "VS Code — reconstructable Cache/CachedData/GPUCache" ;;
    mac-clean-stale-temp.sh)           echo "Stale temp — old /tmp & TMPDIR entries" ;;
    mac-clean-xcode-derived-data.sh)   echo "Xcode DerivedData — build products & indexes" ;;
    mac-clean-xcode-device-support.sh) echo "Xcode iOS DeviceSupport — old symbol bundles (>30d)" ;;
    mac-clean-xcode-simulators.sh)     echo "Xcode simulators — remove unavailable devices" ;;
    mac-clean-xcode-test-clones.sh)    echo "Xcode test clones — leftover clone data" ;;
    *)                                 echo "$1" ;;
  esac
}

# Add a child script here only after its behavior has been reviewed and approved.
STANDARD_CLEANERS=(
  "$SCRIPT_DIR/mac-clean-homebrew.sh"
  "$SCRIPT_DIR/mac-clean-browser-caches.sh"
  "$SCRIPT_DIR/mac-clean-claude-cache.sh"
  "$SCRIPT_DIR/mac-clean-codex-cache.sh"
  "$SCRIPT_DIR/mac-clean-copilot-index-cache.sh"
  "$SCRIPT_DIR/mac-clean-docker-build-cache.sh"
  "$SCRIPT_DIR/mac-clean-nuget-transient.sh"
  "$SCRIPT_DIR/mac-clean-npm-cache.sh"
  "$SCRIPT_DIR/mac-clean-pip-cache.sh"
  "$SCRIPT_DIR/mac-clean-rider-caches.sh"
  "$SCRIPT_DIR/mac-clean-yarn-cache.sh"
  "$SCRIPT_DIR/mac-clean-swiftpm-cache.sh"
  "$SCRIPT_DIR/mac-clean-go-build-cache.sh"
  "$SCRIPT_DIR/mac-clean-vscode-caches.sh"
  "$SCRIPT_DIR/mac-clean-stale-temp.sh"
  "$SCRIPT_DIR/mac-clean-xcode-derived-data.sh"
  "$SCRIPT_DIR/mac-clean-xcode-device-support.sh"
  "$SCRIPT_DIR/mac-clean-xcode-simulators.sh"
  "$SCRIPT_DIR/mac-clean-xcode-test-clones.sh"
)

FULL_CLEANERS=(
)

list_cleaners() {
  local cleaner

  echo "Standard:"
  if (( ${#STANDARD_CLEANERS[@]} == 0 )); then
    echo "  (none)"
  else
    for cleaner in "${STANDARD_CLEANERS[@]}"; do
      printf '  - %s\n' "$(basename "$cleaner")"
    done
  fi

  echo "Full-only:"
  if (( ${#FULL_CLEANERS[@]} == 0 )); then
    echo "  (none)"
  else
    for cleaner in "${FULL_CLEANERS[@]}"; do
      printf '  - %s\n' "$(basename "$cleaner")"
    done
  fi
}

# Step 1: choose scope. Returns 0 for "All", 1 for custom segment selection, 2 for cancel.
prompt_scope() {
  local choice
  choice="$(printf '%s\n' "All — run the standard cleanup" "Select specific segments…" |
    fzf --height=40% --reverse --prompt='Scope > ' \
      --header='mac-clean: choose cleanup scope (Enter to confirm, ESC to cancel)')" || return 2
  [[ "$choice" == All* ]] && return 0
  return 1
}

# Step 2: multi-select segments. Prints selected cleaner paths (one per line).
prompt_segments() {
  local master=() c
  master=("${STANDARD_CLEANERS[@]}")
  (( ${#FULL_CLEANERS[@]} > 0 )) && master+=("${FULL_CLEANERS[@]}")

  {
    for c in "${master[@]}"; do
      printf '%s\t%s\n' "$c" "$(describe "$(basename "$c")")"
    done
  } | fzf --multi --delimiter='\t' --with-nth='2..' \
      --height=60% --reverse --prompt='Segments > ' \
      --header='TAB toggles a segment, Enter confirms, ESC cancels' |
    cut -f1
}

main() {
  local mode="standard"
  local verbose=0
  local want_full=0
  local cleaner
  local cleaner_name
  local index
  local status
  local cleaners=()
  local line
  local scope_rc
  local arg
  local seg_labels=()
  local seg_freed=()
  local out_file=""
  local before_kib
  local after_kib
  local delta_kib
  local total_kib=0

  [[ "$(uname -s)" == "Darwin" ]] || die "mac-clean only runs on macOS."

  for arg in "$@"; do
    case "$arg" in
      --full)
        want_full=1
        ;;
      --list)
        list_cleaners
        exit 0
        ;;
      -v | --verbose)
        verbose=1
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $arg (use --help)"
        ;;
    esac
  done

  if (( want_full )); then
    mode="full"
  elif [[ -t 0 && -t 1 ]] && command -v fzf >/dev/null 2>&1; then
    mode="interactive"
  fi

  if [[ "$mode" == "interactive" ]]; then
    scope_rc=0
    prompt_scope || scope_rc=$?
    case "$scope_rc" in
      0)
        cleaners=("${STANDARD_CLEANERS[@]}")
        ;;
      1)
        while IFS= read -r line; do
          [[ -n "$line" ]] && cleaners+=("$line")
        done < <(prompt_segments)
        if (( ${#cleaners[@]} == 0 )); then
          echo "No segments selected. Nothing to do."
          exit 0
        fi
        ;;
      *)
        echo "Cancelled."
        exit 0
        ;;
    esac
  else
    if (( ${#STANDARD_CLEANERS[@]} > 0 )); then
      cleaners=("${STANDARD_CLEANERS[@]}")
    fi
    if [[ "$mode" == "full" ]] && (( ${#FULL_CLEANERS[@]} > 0 )); then
      cleaners+=("${FULL_CLEANERS[@]}")
    fi
  fi

  if (( ${#cleaners[@]} == 0 )); then
    echo "No macOS cleanup items have been approved yet."
    exit 0
  fi

  for cleaner in "${cleaners[@]}"; do
    [[ "$cleaner" == "$SCRIPT_DIR/"* ]] || die "Cleaner is outside the scripts directory: $cleaner"
    [[ -f "$cleaner" ]] || die "Cleaner does not exist: $cleaner"
    [[ -x "$cleaner" ]] || die "Cleaner is not executable: $cleaner"
  done

  echo "mac-clean ($mode): ${#cleaners[@]} selected item(s)"

  for index in "${!cleaners[@]}"; do
    cleaner="${cleaners[$index]}"
    cleaner_name="$(basename "$cleaner")"

    echo
    printf '[%d/%d] %s\n' "$((index + 1))" "${#cleaners[@]}" "$(short_label "$cleaner_name")"

    before_kib="$(free_kib)"
    status=0
    if (( verbose )); then
      "$cleaner" || status=$?
    else
      out_file="$(mktemp -t mac-clean-out)"
      "$cleaner" >"$out_file" 2>&1 || status=$?
    fi
    after_kib="$(free_kib)"
    delta_kib="$((after_kib - before_kib))"

    if (( status == 0 )); then
      total_kib="$((total_kib + delta_kib))"
      seg_labels+=("$(short_label "$cleaner_name")")
      seg_freed+=("$delta_kib")
      printf '  ✓ freed %s\n' "$(format_kib "$delta_kib")"
      [[ -n "$out_file" ]] && rm -f -- "$out_file"
      out_file=""
    else
      if [[ -n "$out_file" ]]; then
        echo "--- output from $cleaner_name ---" >&2
        cat "$out_file" >&2
        echo "--- end output ---" >&2
        rm -f -- "$out_file"
        out_file=""
      fi
      echo "✗ Failed: $cleaner_name (exit $status). Stopping." >&2
      exit "$status"
    fi
  done

  echo
  echo "mac-clean completed."
  echo
  echo "Space freed (approximate):"
  for index in "${!seg_labels[@]}"; do
    printf '  %-26s %10s\n' "${seg_labels[$index]}" "$(format_kib "${seg_freed[$index]}")"
  done
  printf '  %-26s %10s\n' "Total" "$(format_kib "$total_kib")"
}

main "$@"
