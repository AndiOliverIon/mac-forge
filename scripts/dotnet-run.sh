#!/usr/bin/env bash
set -euo pipefail

die() {
	echo "ERROR: $*" >&2
	exit 1
}

usage() {
	cat <<EOF
Usage: $(basename "$0") [--profile <name>] [dotnet run arguments]

Starts the ASP.NET Core backend of the solution you are currently in, from the
terminal. The repository is detected from the current directory, and the web
startup project (the single Microsoft.NET.Sdk.Web project) is discovered
automatically. Rider and this command share the project's launchSettings.json
profiles. Extra arguments are passed straight through to dotnet run.

Examples:
  $(basename "$0")
  $(basename "$0") --profile http-entra-local
  $(basename "$0") --profile http-migrations --no-build
  $(basename "$0") --no-build
  $(basename "$0") -- --urls http://localhost:5005

Environment overrides:
  DR_ROOT             Repository root (defaults to the current git repository)
  DR_PROJECT          Startup project path (skips auto-detection)
  DR_PROFILE          launchSettings.json profile (same as --profile)
EOF
}

PROFILE="${DR_PROFILE:-}"
case "${1:-}" in
--help | -h)
	usage
	exit 0
	;;
--profile | -p)
	[[ -n "${2:-}" ]] || die "--profile requires a profile name"
	PROFILE="$2"
	shift 2
	;;
--profile=*)
	PROFILE="${1#*=}"
	[[ -n "$PROFILE" ]] || die "--profile requires a profile name"
	shift
	;;
esac

command -v dotnet >/dev/null 2>&1 || die "dotnet executable not found"

# Resolve the repository root from the current directory.
ROOT="${DR_ROOT:-}"
if [[ -z "$ROOT" ]]; then
	ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
[[ -n "$ROOT" ]] || die "Not inside a git repository; cd into a solution or set DR_ROOT"
[[ -d "$ROOT" ]] || die "Repository root not found: $ROOT"

# Discover the web startup project (single Microsoft.NET.Sdk.Web csproj).
PROJECT="${DR_PROJECT:-}"
if [[ -z "$PROJECT" ]]; then
	mapfile -t WEB_PROJECTS < <(
		grep -rl --include='*.csproj' 'Sdk="Microsoft.NET.Sdk.Web"' "$ROOT" 2>/dev/null |
			grep -Ev '/(bin|obj|node_modules)/' |
			grep -Eiv '(test|tests)\.csproj$'
	)
	case ${#WEB_PROJECTS[@]} in
	0) die "No Microsoft.NET.Sdk.Web startup project found under $ROOT" ;;
	1) PROJECT="${WEB_PROJECTS[0]}" ;;
	*)
		echo "Multiple web startup projects found under $ROOT:" >&2
		printf '  %s\n' "${WEB_PROJECTS[@]}" >&2
		die "Set DR_PROJECT to choose one"
		;;
	esac
fi
[[ -f "$PROJECT" ]] || die "Startup project not found: $PROJECT"

# Sensible defaults for projects without launch settings.
export DOTNET_ENVIRONMENT="${DOTNET_ENVIRONMENT:-Development}"
export ASPNETCORE_ENVIRONMENT="${ASPNETCORE_ENVIRONMENT:-Development}"

echo "Repository:  $ROOT"
echo "Project:     $PROJECT"
echo "Environment: $ASPNETCORE_ENVIRONMENT"
[[ -n "$PROFILE" ]] && echo "Profile:     $PROFILE"

RUN_ARGS=(--project "$PROJECT")
if [[ -n "$PROFILE" ]]; then
	LAUNCH_SETTINGS="$(dirname "$PROJECT")/Properties/launchSettings.json"
	[[ -f "$LAUNCH_SETTINGS" ]] || die "Launch settings not found: $LAUNCH_SETTINGS"
	RUN_ARGS+=(--launch-profile "$PROFILE")
fi

exec dotnet run "${RUN_ARGS[@]}" "$@"
