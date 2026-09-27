#!/usr/bin/env bash
set -euo pipefail

die() {
	echo "ERROR: $*" >&2
	exit 1
}

read_launch_profile_names() {
	local launch_settings="$1"

	if command -v jq >/dev/null 2>&1; then
		jq -r '.profiles | to_entries[] | select(.value.commandName == "Project") | .key' "$launch_settings"
		return
	fi

	if command -v python3 >/dev/null 2>&1; then
		python3 - "$launch_settings" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8-sig") as launch_settings_file:
    profiles = json.load(launch_settings_file).get("profiles", {})

for name, profile in profiles.items():
    if profile.get("commandName") == "Project":
        print(name)
PY
		return
	fi

	die "Reading launchSettings.json requires jq or python3"
}

apply_run_env() {
	local run_file="$1"
	local name value line

	while IFS= read -r line; do
		name="$(sed -n 's/.*<env name="\([^"]*\)".*/\1/p' <<<"$line")"
		value="$(sed -n 's/.*value="\([^"]*\)".*/\1/p' <<<"$line")"
		[[ -n "$name" ]] || continue
		[[ -n "${!name:-}" ]] || export "$name=$value"
	done < <(grep '<env ' "$run_file" 2>/dev/null)
}

usage() {
	cat <<EOF
Usage: $(basename "$0") [--profile <name>] [dotnet run arguments]

Starts the ASP.NET Core backend of the solution you are currently in, from the
terminal. The repository is detected from the current directory, and the web
startup project (the single Microsoft.NET.Sdk.Web project) is discovered
automatically. Configurations are discovered from the project's
launchSettings.json and matching Rider .run files. A single configuration is
selected automatically; multiple configurations are presented as a menu.
Extra arguments are passed straight through to dotnet run.

Examples:
  $(basename "$0")
  $(basename "$0") --profile http-entra-local
  $(basename "$0") --profile http-migrations --no-build
  $(basename "$0") --no-build
  $(basename "$0") -- --urls http://localhost:5005

Environment overrides:
  DR_ROOT             Repository root (defaults to the current git repository)
  DR_PROJECT          Startup project path (skips auto-detection)
  DR_PROFILE          Configuration name (same as --profile)
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

CONFIG_NAMES=()
CONFIG_TYPES=()
CONFIG_FILES=()
LAUNCH_SETTINGS="$(dirname "$PROJECT")/Properties/launchSettings.json"
if [[ -f "$LAUNCH_SETTINGS" ]]; then
	while IFS= read -r profile_name; do
		[[ -n "$profile_name" ]] || continue
		CONFIG_NAMES+=("$profile_name")
		CONFIG_TYPES+=("launchSettings")
		CONFIG_FILES+=("$LAUNCH_SETTINGS")
	done < <(read_launch_profile_names "$LAUNCH_SETTINGS")
fi

if [[ -d "$ROOT/.run" ]]; then
	project_basename="$(basename "$PROJECT")"
	for run_file in "$ROOT"/.run/*.run.xml; do
		[[ -f "$run_file" ]] || continue
		grep -Fq "$project_basename" "$run_file" || continue
		run_name="$(sed -n 's/.*<configuration[^>]* name="\([^"]*\)".*/\1/p' "$run_file" | head -1)"
		[[ -n "$run_name" ]] || continue
		CONFIG_NAMES+=("$run_name")
		CONFIG_TYPES+=("Rider .run")
		CONFIG_FILES+=("$run_file")
	done
fi

SELECTED_INDEX=-1
if [[ -n "$PROFILE" ]]; then
	for index in "${!CONFIG_NAMES[@]}"; do
		if [[ "${CONFIG_NAMES[$index]}" == "$PROFILE" ]]; then
			SELECTED_INDEX="$index"
			break
		fi
	done
	[[ "$SELECTED_INDEX" -ge 0 ]] || die "Configuration not found: $PROFILE"
elif [[ "${#CONFIG_NAMES[@]}" -eq 1 ]]; then
	SELECTED_INDEX=0
elif [[ "${#CONFIG_NAMES[@]}" -gt 1 ]]; then
	[[ -t 0 && -t 1 ]] || die "Multiple configurations found; use --profile <name>"

	echo "Available configurations:"
	for index in "${!CONFIG_NAMES[@]}"; do
		printf '  %d) %s [%s]\n' "$((index + 1))" "${CONFIG_NAMES[$index]}" "${CONFIG_TYPES[$index]}"
	done

	while true; do
		read -r -p "Choose configuration [1-${#CONFIG_NAMES[@]}]: " selection
		if [[ "$selection" =~ ^[0-9]+$ ]] &&
			((selection >= 1 && selection <= ${#CONFIG_NAMES[@]})); then
			SELECTED_INDEX="$((selection - 1))"
			break
		fi
		echo "Please enter a number from 1 to ${#CONFIG_NAMES[@]}." >&2
	done
fi

RUN_ARGS=(--project "$PROJECT")
if [[ "$SELECTED_INDEX" -ge 0 ]]; then
	PROFILE="${CONFIG_NAMES[$SELECTED_INDEX]}"
	CONFIG_TYPE="${CONFIG_TYPES[$SELECTED_INDEX]}"
	CONFIG_FILE="${CONFIG_FILES[$SELECTED_INDEX]}"

	if [[ "$CONFIG_TYPE" == "launchSettings" ]]; then
		RUN_ARGS+=(--launch-profile "$PROFILE")
	else
		apply_run_env "$CONFIG_FILE"
	fi
fi

# Sensible defaults for projects without an environment in their configuration.
export DOTNET_ENVIRONMENT="${DOTNET_ENVIRONMENT:-Development}"
export ASPNETCORE_ENVIRONMENT="${ASPNETCORE_ENVIRONMENT:-Development}"

echo "Repository:  $ROOT"
echo "Project:     $PROJECT"
echo "Environment: $ASPNETCORE_ENVIRONMENT"
[[ "$SELECTED_INDEX" -ge 0 ]] && echo "Configuration: $PROFILE [$CONFIG_TYPE]"

exec dotnet run "${RUN_ARGS[@]}" "$@"
