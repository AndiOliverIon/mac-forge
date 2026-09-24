#!/usr/bin/env bash
set -euo pipefail

die() {
	echo "Error: $*" >&2
	exit 1
}

usage() {
	cat <<'EOF'
Usage:
  publish-tt          Publish .NET 8 from development to the production v2 image.
  publish-tt net10    Publish .NET 10 from aoi/net10-upgrade to isolated trial images.
EOF
}

TIMETRACK_ROOT="${TIMETRACK_ROOT:-$HOME/work/ardis.timetrack}"

if [[ $# -gt 1 ]]; then
	usage >&2
	die "Expected no argument or 'net10'."
fi

mode="${1:-net8}"
case "$mode" in
net8)
	expected_branch="development"
	expected_target_framework="net8.0"
	image_tag="v2"
	;;
net10)
	expected_branch="aoi/net10-upgrade"
	expected_target_framework="net10.0"
	image_tag="net10-trial"
	;;
-h | --help)
	usage
	exit 0
	;;
*)
	usage >&2
	die "Unsupported publish mode: $mode"
	;;
esac

[[ -d "$TIMETRACK_ROOT" ]] || die "Timetrack repo not found: $TIMETRACK_ROOT"

cd "$TIMETRACK_ROOT"

[[ -x ./buildsolution.sh ]] || die "Solution build script is not executable: $TIMETRACK_ROOT/buildsolution.sh"
[[ -x ./Ardis.Timetrack/build-docker.sh ]] || die "Docker build script is not executable: $TIMETRACK_ROOT/Ardis.Timetrack/build-docker.sh"

current_branch="$(git symbolic-ref --quiet --short HEAD)" || die "Timetrack must be on a branch, not a detached HEAD."
[[ "$current_branch" == "$expected_branch" ]] || die "Mode '$mode' requires branch '$expected_branch'; current branch is '$current_branch'."

if [[ -n "$(git status --porcelain)" ]]; then
	die "Timetrack working tree must be clean before publishing."
fi

target_framework="$(sed -nE 's|.*<TargetFramework>([^<]+)</TargetFramework>.*|\1|p' ./Ardis.Timetrack/Ardis.Timetrack.csproj | head -n 1)"
[[ "$target_framework" == "$expected_target_framework" ]] || die "Mode '$mode' requires TargetFramework '$expected_target_framework'; found '${target_framework:-none}'."

echo "Publishing Timetrack mode: $mode"
echo "Source branch: $current_branch"
echo "Target framework: $target_framework"
echo "Image tag: portainer.ardis.eu:5000/ardis-timetrack:$image_tag"

echo "Running Timetrack solution build..."
./buildsolution.sh

echo "Running Timetrack Docker build and push..."
if [[ "$mode" == "net8" ]]; then
	TIMETRACK_IMAGE_TAG="$image_tag" TIMETRACK_ALLOW_PRODUCTION_TAG=true ./Ardis.Timetrack/build-docker.sh
else
	env -u TIMETRACK_ALLOW_PRODUCTION_TAG TIMETRACK_IMAGE_TAG="$image_tag" ./Ardis.Timetrack/build-docker.sh
fi
