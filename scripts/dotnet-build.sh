#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(pwd -P)"
CONFIGURATION="Debug"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage: dotnet-build.sh [options]

Build the dotnet solution/project found in the current directory.

Looks for .sln and .slnx files first; if none are found, falls back to
.csproj files. If exactly one is found it is built directly. If several
are found, fzf is used to pick one.

Options:
  -r, --release   Build in Release configuration (default: Debug).
  -h, --help      Show this help.
USAGE
}

while (( $# > 0 )); do
  case "$1" in
    -r|--release)
      CONFIGURATION="Release"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1 (use --help)"
      ;;
  esac
  shift
done

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."
}

require_cmd dotnet

mapfile -t candidates < <(find "$ROOT_DIR" -maxdepth 1 -type f \( -name '*.sln' -o -name '*.slnx' \) | sort)

if (( ${#candidates[@]} == 0 )); then
  mapfile -t candidates < <(find "$ROOT_DIR" -maxdepth 1 -type f -name '*.csproj' | sort)
fi

if (( ${#candidates[@]} == 0 )); then
  die "No .sln, .slnx, or .csproj files found in $ROOT_DIR"
fi

target=""
if (( ${#candidates[@]} == 1 )); then
  target="${candidates[0]}"
else
  require_cmd fzf
  target="$(printf '%s\n' "${candidates[@]}" | sed "s#^$ROOT_DIR/##" \
    | fzf --prompt='Select project to build > ' --height=40% --reverse)"
  [[ -n "$target" ]] || { echo "Cancelled."; exit 0; }
  target="$ROOT_DIR/$target"
fi

echo "Building: ${target#"$ROOT_DIR"/} ($CONFIGURATION)"
dotnet build "$target" -c "$CONFIGURATION"
