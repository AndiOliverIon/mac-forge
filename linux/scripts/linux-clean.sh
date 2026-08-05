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

Run the approved Linux cleanup scripts in order.

Options:
  -n, --dry-run Preview every selected cleaner without deleting.
  --full        Include full-only desktop cache cleanup.
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
  cleaners=("${STANDARD_CLEANERS[@]}")
  (( full )) && cleaners+=("${FULL_CLEANERS[@]}")
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
