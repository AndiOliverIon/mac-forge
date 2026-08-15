#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

die() {
  echo "✗ $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: linux-clean [--dry-run] [--full] [--list]

Run the approved Linux cleanup scripts.

With no arguments (in an interactive terminal with fzf installed), linux-clean
opens a picker: choose "All" to run the standard cleanup, or select specific
segments with TAB and clean only those.

Options:
  -n, --dry-run Preview every selected cleaner without deleting.
  --full        Include full-only desktop cache cleanup (non-interactive).
  --list        Show approved cleaners and their classification.
  -h, --help    Show this help.
EOF
}

STANDARD_CLEANERS=(
  "$SCRIPT_DIR/linux-clean-browser-caches.sh"
  "$SCRIPT_DIR/linux-clean-claude-cache.sh"
  "$SCRIPT_DIR/linux-clean-copilot-index-cache.sh"
  "$SCRIPT_DIR/linux-clean-docker-build-cache.sh"
  "$SCRIPT_DIR/linux-clean-nuget-transient.sh"
  "$SCRIPT_DIR/linux-clean-npm-cache.sh"
  "$SCRIPT_DIR/linux-clean-rider-caches.sh"
  "$SCRIPT_DIR/linux-clean-yarn-cache.sh"
  "$SCRIPT_DIR/linux-clean-stale-temp.sh"
)

FULL_CLEANERS=(
  "$SCRIPT_DIR/linux-clean-desktop-caches.sh"
)

list_cleaners() {
  local cleaner
  echo "Standard:"
  for cleaner in "${STANDARD_CLEANERS[@]}"; do printf '  - %s\n' "$(basename "$cleaner")"; done
  echo "Full-only:"
  for cleaner in "${FULL_CLEANERS[@]}"; do printf '  - %s\n' "$(basename "$cleaner")"; done
}

# Friendly, human-readable description for each cleaner.
describe() {
  case "$1" in
    linux-clean-browser-caches.sh)       echo "Browser caches — Chrome/Brave cache & code cache" ;;
    linux-clean-claude-cache.sh)         echo "Claude cache — staging/temp files" ;;
    linux-clean-copilot-index-cache.sh)  echo "Copilot index cache — project context & index" ;;
    linux-clean-docker-build-cache.sh)   echo "Docker build cache — old buildx layers" ;;
    linux-clean-nuget-transient.sh)      echo "NuGet transient — http-cache, scratch & plugin cache" ;;
    linux-clean-npm-cache.sh)            echo "npm cache — global download cache" ;;
    linux-clean-rider-caches.sh)         echo "JetBrains Rider — caches, indexes & host temp" ;;
    linux-clean-yarn-cache.sh)           echo "Yarn cache — global package cache" ;;
    linux-clean-stale-temp.sh)           echo "Stale temp — old /tmp entries" ;;
    linux-clean-desktop-caches.sh)       echo "Desktop caches — thumbnails & shader caches (full-only)" ;;
    *)                                   echo "$1" ;;
  esac
}

# Step 1: choose scope. Returns 0 for "All", 1 for custom selection, 2 for cancel.
prompt_scope() {
  local choice
  choice="$(printf '%s\n' "All — run the standard cleanup" "Select specific segments…" |
    fzf --height=40% --reverse --prompt='Scope > ' \
      --header='linux-clean: choose cleanup scope (Enter to confirm, ESC to cancel)')" || return 2
  [[ "$choice" == All* ]] && return 0
  return 1
}

# Step 2: multi-select segments. Prints selected cleaner paths (one per line).
prompt_segments() {
  local master=() c
  master=("${STANDARD_CLEANERS[@]}" "${FULL_CLEANERS[@]}")

  {
    for c in "${master[@]}"; do
      printf '%s\t%s\n' "$c" "$(describe "$(basename "$c")")"
    done
  } | fzf --multi --delimiter='\t' --with-nth='2..' \
      --height=60% --reverse --prompt='Segments > ' \
      --header='TAB toggles a segment, Enter confirms, ESC cancels' |
    cut -f1
}

sum_paths_kib() {
  local path total=0

  for path in "$@"; do
    [[ -e "$path" ]] || continue
    total="$((total + $(du -sk -- "$path" 2>/dev/null | awk '{print $1}')))"
  done
  echo "$total"
}

cleaner_size_kib() {
  local cleaner_name="$1"
  local cache_dir path total=0
  local paths=()

  case "$cleaner_name" in
    linux-clean-browser-caches.sh)
      for cache_dir in \
        "$HOME/.cache/google-chrome" \
        "$HOME/.cache/BraveSoftware/Brave-Browser"; do
        while IFS= read -r -d '' path; do paths+=("$path"); done < <(
          find "$cache_dir" -mindepth 2 -maxdepth 2 -type d \
            \( -name Cache -o -name 'Code Cache' \) -print0 2>/dev/null
        )
      done
      ;;
    linux-clean-claude-cache.sh)
      paths=("$HOME/.cache/claude/staging")
      ;;
    linux-clean-copilot-index-cache.sh)
      paths=(
        "$HOME/.cache/github-copilot/project-context"
        "$HOME/.cache/github-copilot/project-index"
      )
      ;;
    linux-clean-docker-build-cache.sh)
      if docker info >/dev/null 2>&1; then
        docker buildx du --filter "until=168h" --format '{{.Size}}' 2>/dev/null |
          awk '
            function kib(value, unit) {
              if (unit == "B") return value / 1024
              if (unit == "kB" || unit == "KB") return value
              if (unit == "MB") return value * 1024
              if (unit == "GB") return value * 1048576
              if (unit == "TB") return value * 1073741824
              return 0
            }
            /^[0-9.]+[A-Za-z]+$/ {
              value = $0
              unit = $0
              sub(/[A-Za-z]+$/, "", value)
              sub(/^[0-9.]+/, "", unit)
              total += kib(value, unit)
            }
            END { printf "%.0f\n", total }
          '
        return
      fi
      echo 0
      return
      ;;
    linux-clean-nuget-transient.sh)
      paths=(
        "$HOME/.local/share/NuGet/http-cache"
        "/tmp/NuGetScratch${USER}"
        "$HOME/.local/share/NuGet/plugin-cache"
      )
      ;;
    linux-clean-npm-cache.sh)
      cache_dir="$(npm config get cache 2>/dev/null || true)"
      [[ "$cache_dir" == /* ]] && paths=("$cache_dir")
      ;;
    linux-clean-rider-caches.sh)
      while IFS= read -r -d '' path; do paths+=("$path"); done < <(
        find "$HOME/.cache/JetBrains" -mindepth 2 -maxdepth 3 -type d \
          \( -path '*/Rider20*/caches' -o -path '*/Rider20*/index' \
          -o -path '*/Rider20*/resharper-host/local' \
          -o -path '*/Rider20*/resharper-host/temp' \
          -o -path '*/Rider20*/tmp' \) -print0 2>/dev/null
      )
      ;;
    linux-clean-yarn-cache.sh)
      paths=("$HOME/.cache/yarn")
      ;;
    linux-clean-stale-temp.sh)
      while IFS= read -r -d '' path; do
        cache_dir="${path##*/}"
        cache_dir="${cache_dir,,}"
        total=10080
        case "$cache_dir" in
          .agents | .codex | codex* | claude* | github-copilot* | copilot*)
            total=1440
            ;;
        esac
        if find "$path" -mmin "-$total" -print -quit 2>/dev/null | grep -q .; then
          continue
        fi
        paths+=("$path")
      done < <(find /tmp -mindepth 1 -maxdepth 1 -user "$(id -u)" -print0 2>/dev/null)
      ;;
    linux-clean-desktop-caches.sh)
      paths=(
        "$HOME/.cache/thumbnails"
        "$HOME/.cache/mesa_shader_cache"
        "$HOME/.cache/qtshadercache-x86_64-little_endian-lp64"
      )
      ;;
  esac

  total="$(sum_paths_kib "${paths[@]}")"
  echo "$total"
}

format_size() {
  awk -v kib="$1" '
    BEGIN {
      if (kib >= 1048576) printf "%.2f GiB", kib / 1048576
      else if (kib >= 1024) printf "%.1f MiB", kib / 1024
      else printf "%d KiB", kib
    }
  '
}

main() {
  local dry_run=0 full=0 list=0 cleaner cleaner_name status before after gain total_gain=0
  local cleaners=()
  local child_args=()
  local summary_names=()
  local summary_gains=()
  local argc=$#
  local line scope_rc

  [[ "$(uname -s)" == "Linux" ]] || die "linux-clean only runs on Linux."
  while (( $# > 0 )); do
    case "$1" in
      -n | --dry-run) dry_run=1 ;;
      --full) full=1 ;;
      --list) list=1 ;;
      -h | --help) usage; exit 0 ;;
      *) die "Unknown argument: $1 (use --help)" ;;
    esac
    shift
  done

  (( list )) && { list_cleaners; exit 0; }

  if (( argc == 0 )) && [[ -t 0 && -t 1 ]] && command -v fzf >/dev/null 2>&1; then
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
    cleaners=("${STANDARD_CLEANERS[@]}")
    (( full )) && cleaners+=("${FULL_CLEANERS[@]}")
  fi
  (( dry_run )) && child_args=(--dry-run)

  for cleaner in "${cleaners[@]}"; do
    [[ "$cleaner" == "$SCRIPT_DIR/"* ]] || die "Cleaner is outside the Linux scripts directory: $cleaner"
    [[ -f "$cleaner" && -x "$cleaner" ]] || die "Cleaner is missing or not executable: $cleaner"
  done

  echo "linux-clean ($([[ $full == 1 ]] && echo full || echo standard), $([[ $dry_run == 1 ]] && echo dry-run || echo apply)): ${#cleaners[@]} approved item(s)"
  for cleaner in "${cleaners[@]}"; do
    cleaner_name="$(basename "$cleaner")"
    before="$(cleaner_size_kib "$cleaner_name")"
    echo
    echo "[$cleaner_name]"
    if "$cleaner" "${child_args[@]}"; then
      echo "✓ Completed: $cleaner_name"
    else
      status=$?
      echo "✗ Failed: $cleaner_name (exit $status). Stopping." >&2
      exit "$status"
    fi

    if (( dry_run )); then
      gain="$before"
    else
      after="$(cleaner_size_kib "$cleaner_name")"
      (( before > after )) && gain="$((before - after))" || gain=0
    fi
    summary_names+=("$cleaner_name")
    summary_gains+=("$gain")
    total_gain="$((total_gain + gain))"
  done
  echo
  echo "linux-clean completed."
  echo
  if (( dry_run )); then
    echo "Estimated gain:"
  else
    echo "Measured gain:"
  fi
  for status in "${!summary_names[@]}"; do
    printf '  %-45s %10s\n' "${summary_names[$status]}" \
      "$(format_size "${summary_gains[$status]}")"
  done
  printf '  %-45s %10s\n' "Total" "$(format_size "$total_gain")"
}

main "$@"
