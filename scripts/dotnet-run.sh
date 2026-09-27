#!/usr/bin/env bash
set -euo pipefail

die() {
	echo "ERROR: $*" >&2
	exit 1
}

usage() {
	cat <<EOF
Usage: $(basename "$0") [dotnet run arguments]

Starts the ASP.NET Core backend of the solution you are currently in, from the
terminal. The repository is detected from the current directory, and the web
startup project (the single Microsoft.NET.Sdk.Web project) is discovered
automatically. If the repository has a Rider ".run/*.run.xml" configuration for
that project, its environment variables are reused; otherwise Development is
assumed. Extra arguments are passed straight through to dotnet run.

Examples:
  $(basename "$0")
  $(basename "$0") --no-build
  $(basename "$0") -- --urls http://localhost:5005

Environment overrides:
  DR_ROOT             Repository root (defaults to the current git repository)
  DR_PROJECT          Startup project path (skips auto-detection)
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
	usage
	exit 0
fi

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

# Reuse env from a matching Rider run configuration when one exists.
apply_run_env() {
	local run_file="$1"
	local name value line
	while IFS= read -r line; do
		name="$(sed -n 's/.*<env name="\([^"]*\)".*/\1/p' <<<"$line")"
		value="$(sed -n 's/.*value="\([^"]*\)".*/\1/p' <<<"$line")"
		[[ -n "$name" ]] || continue
		# Existing environment wins; only fill what is unset.
		[[ -n "${!name:-}" ]] || export "$name=$value"
	done < <(grep '<env ' "$run_file" 2>/dev/null)
}

RUN_ENV_SOURCE=""
if [[ -d "$ROOT/.run" ]]; then
	project_basename="$(basename "$PROJECT")"
	for run_file in "$ROOT"/.run/*.run.xml; do
		[[ -f "$run_file" ]] || continue
		if grep -q "$project_basename" "$run_file"; then
			apply_run_env "$run_file"
			RUN_ENV_SOURCE="$run_file"
			break
		fi
	done
fi

# Sensible defaults when no run configuration supplied them.
export DOTNET_ENVIRONMENT="${DOTNET_ENVIRONMENT:-Development}"
export ASPNETCORE_ENVIRONMENT="${ASPNETCORE_ENVIRONMENT:-Development}"

echo "Repository:  $ROOT"
echo "Project:     $PROJECT"
echo "Environment: $ASPNETCORE_ENVIRONMENT"
[[ -n "$RUN_ENV_SOURCE" ]] && echo "Run config:  $RUN_ENV_SOURCE"

exec dotnet run --project "$PROJECT" "$@"
