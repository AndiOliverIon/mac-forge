#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bl-clean [--dry-run]

Preview and remove BookingLounge's disposable release-gate output and build
caches after typing CLEAN. Use --dry-run to inspect without deleting anything.
Set BL_REPO to select a different BookingLounge checkout.
EOF
}

die() {
  printf 'bl-clean: %s\n' "$*" >&2
  exit 1
}

dry_run=0
case "${1:-}" in
  '') ;;
  -n|--dry-run) dry_run=1 ;;
  -h|--help) usage; exit 0 ;;
  *) die 'Use --dry-run or --help.' ;;
esac
(( $# <= 1 )) || die 'Too many arguments.'

command -v git >/dev/null || die 'git is required.'
command -v lsof >/dev/null || die 'lsof is required.'

repository_input="${BL_REPO:-${HOME}/projects/bookinglounge}"
[[ -d "$repository_input" && ! -L "$repository_input" ]] || die "Repository not found or is a symlink: $repository_input"
repository="$(cd -P -- "$repository_input" && pwd)"
[[ "$repository" != / ]] || die 'Refusing to clean the filesystem root.'
[[ "$(git -C "$repository" rev-parse --show-toplevel 2>/dev/null)" == "$repository" ]] || die 'BL_REPO must be a Git checkout root.'
[[ -f "$repository/release-gate/README.md" && -x "$repository/Backend/deploy/test-all.sh" ]] || die 'BL_REPO is not a BookingLounge gate checkout.'

# This is an allowlist of output locations, never a recursive search for names.
# Keep private review material and signed release files outside this list.
targets=(
  release-gate/temporary
  Backend/deploy/reports
  Backend/LegacyUpgradeSeeder/bin
  Backend/LegacyUpgradeSeeder/obj
  Backend/LegacyUpgradeVerifier/bin
  Backend/LegacyUpgradeVerifier/obj
  Backend/BookingLounge.PlaywrightHost/bin
  Backend/BookingLounge.PlaywrightHost/obj
  Backend/BookingLounge.Api/bin
  Backend/BookingLounge.Api/obj
  Backend/BookingLounge.Api.Tests/bin
  Backend/BookingLounge.Api.Tests/obj
  Backend/BookingLounge.Api.Tests/TestResults
  booking.lounge.portal/.angular/cache
  booking.lounge.portal/dist
  booking.lounge.portal/playwright-results
)

existing=()
total_kib=0
for relative in "${targets[@]}"; do
  target="$repository/$relative"
  [[ -e "$target" || -L "$target" ]] || continue
  [[ -d "$target" && ! -L "$target" ]] || die "Refusing non-directory or symlink: $relative"
  [[ "$(cd -P -- "$(dirname "$target")" && pwd)" == "$(dirname "$target")" ]] || die "Refusing symlinked parent: $relative"
  [[ -z "$(git -C "$repository" ls-files -- "$relative")" ]] || die "Refusing tracked content: $relative"
  size_kib="$(du -sk "$target" | awk '{print $1}')"
  printf '%8s KiB  %s\n' "$size_kib" "$relative"
  total_kib=$((total_kib + size_kib))
  existing+=("$target")
done

printf 'Total: %s KiB in %s generated directories.\n' "$total_kib" "${#existing[@]}"
if (( ${#existing[@]} == 0 )); then
  exit 0
fi
if (( dry_run )); then
  printf 'Dry run: nothing removed.\n'
  exit 0
fi

printf 'Type CLEAN to remove only the listed directories: '
IFS= read -r answer || die 'Confirmation was not received.'
[[ "$answer" == CLEAN ]] || die 'Cancelled.'

for target in "${existing[@]}"; do
  relative="${target#"$repository"/}"
  [[ -d "$target" && ! -L "$target" ]] || die "Target changed after preview: $relative"
  [[ "$(cd -P -- "$(dirname "$target")" && pwd)" == "$(dirname "$target")" ]] || die "Target parent changed after preview: $relative"
  [[ -z "$(git -C "$repository" ls-files -- "$relative")" ]] || die "Tracked content appeared after preview: $relative"
  if lsof -n -P +D "$target" >/dev/null 2>&1; then
    die "A process is using $target; stop the build/test gate first."
  else
    status=$?
    (( status == 1 )) || die "Could not inspect open files in $target."
  fi
done

for target in "${existing[@]}"; do
  rm -rf -- "$target"
done
mkdir -p -- "$repository/release-gate/temporary"
printf 'Removed %s generated directories; release-gate/temporary is ready for the next run.\n' "${#existing[@]}"
