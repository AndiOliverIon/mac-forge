#!/usr/bin/env bash
set -euo pipefail

die() {
	echo "ERROR: $*" >&2
	exit 1
}

usage() {
	cat <<EOF
Usage: $(basename "$0") [keyword] [dotnet test arguments]

Runs the Ardis Perform unit-test project using the DebugUnitTestLocal configuration.
Without a keyword, all tests run. With a keyword, only tests whose full name
contains that keyword run. Additional arguments are passed directly to dotnet test.

Examples:
  $(basename "$0")
  $(basename "$0") Planner
  $(basename "$0") JobPlannerManagerTests --no-restore

Environment overrides:
  PERFORM_ROOT                Perform repository root
  PERFORM_TEST_PROJECT        Unit-test project path
  PERFORM_TEST_CONFIGURATION  Build configuration
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
	usage
	exit 0
fi

PERFORM_ROOT="${PERFORM_ROOT:-$HOME/work/ardis-perform}"
TEST_PROJECT="${PERFORM_TEST_PROJECT:-$PERFORM_ROOT/Ardis.Perform.UnitTest/Ardis.Perform.UnitTest.csproj}"
TEST_CONFIGURATION="${PERFORM_TEST_CONFIGURATION:-DebugUnitTestLocal}"
FILTER_KEYWORD=""

if [[ $# -gt 0 && "$1" != -* ]]; then
	FILTER_KEYWORD="$1"
	shift

	[[ "$FILTER_KEYWORD" =~ ^[[:alnum:]_.-]+$ ]] || die "Filter keyword may contain only letters, numbers, dots, underscores, and hyphens"
fi

command -v dotnet >/dev/null 2>&1 || die "dotnet executable not found"
[[ -f "$TEST_PROJECT" ]] || die "Unit-test project not found: $TEST_PROJECT"

echo "Project:       $TEST_PROJECT"
echo "Configuration: $TEST_CONFIGURATION"
if [[ -n "$FILTER_KEYWORD" ]]; then
	echo "Filter:        $FILTER_KEYWORD"
	exec dotnet test "$TEST_PROJECT" --configuration "$TEST_CONFIGURATION" --filter "$FILTER_KEYWORD" "$@"
fi

exec dotnet test "$TEST_PROJECT" --configuration "$TEST_CONFIGURATION" "$@"
