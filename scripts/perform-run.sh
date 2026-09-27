#!/usr/bin/env bash
set -euo pipefail

die() {
	echo "ERROR: $*" >&2
	exit 1
}

usage() {
	cat <<EOF
Usage: $(basename "$0") [dotnet run arguments]

Starts the Ardis Perform backend from the terminal, mirroring the Rider
"MacDebug" run configuration (project, working directory, and environment).
Any extra arguments are passed straight through to dotnet run.

Examples:
  $(basename "$0")
  $(basename "$0") --no-build
  $(basename "$0") -- --urls http://localhost:5005

Environment overrides:
  PERFORM_ROOT             Perform repository root
  PERFORM_RUN_PROJECT      Startup project path
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
	usage
	exit 0
fi

PERFORM_ROOT="${PERFORM_ROOT:-$HOME/work/ardis-perform}"
RUN_PROJECT="${PERFORM_RUN_PROJECT:-$PERFORM_ROOT/Ardis.Perform/Ardis.Perform.csproj}"

command -v dotnet >/dev/null 2>&1 || die "dotnet executable not found"
[[ -f "$RUN_PROJECT" ]] || die "Startup project not found: $RUN_PROJECT"

# Environment mirrored from .run/MacDebug.run.xml
export ASMS2_LOCAL_OVERRIDES="${ASMS2_LOCAL_OVERRIDES:-1}"
export DOTNET_ENVIRONMENT="${DOTNET_ENVIRONMENT:-Development}"
export ASPNETCORE_ENVIRONMENT="${ASPNETCORE_ENVIRONMENT:-Development}"
export SKIP_LC_VERIFIER="${SKIP_LC_VERIFIER:-true}"
export LOCAL_OVERRIDES="${LOCAL_OVERRIDES:-1}"
export UNITTEST_USE_MOCK_LICENSE_SERVICE="${UNITTEST_USE_MOCK_LICENSE_SERVICE:-true}"

echo "Project:     $RUN_PROJECT"
echo "Environment: $ASPNETCORE_ENVIRONMENT"

exec dotnet run --project "$RUN_PROJECT" "$@"
