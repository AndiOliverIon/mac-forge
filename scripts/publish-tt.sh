#!/usr/bin/env bash
set -euo pipefail

die() {
	echo "Error: $*" >&2
	exit 1
}

usage() {
	cat <<'EOF'
Usage:
  publish-tt          Publish TimeTrack according to the checked-out branch.

Branches:
  main                Publish .NET 10 to the v2 image.
  development         Publish .NET 10 to the isolated net10-trial image.
  release/1.0.91      Publish the frozen .NET 8 release to the v2 image.
EOF
}

if [[ $# -gt 0 ]]; then
	case "$1" in
	-h | --help)
		usage
		exit 0
		;;
	*)
		usage >&2
		die "Publishing behavior is selected automatically from the current branch."
		;;
	esac
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
timetrack_root="${TIMETRACK_ROOT:-$HOME/work/ardis.timetrack}"
csproj="$timetrack_root/Ardis.Timetrack/Ardis.Timetrack.csproj"

[[ -d "$timetrack_root" ]] || die "Timetrack repo not found: $timetrack_root"
[[ -f "$csproj" ]] || die "Timetrack project not found: $csproj"

cd "$timetrack_root"

current_branch="$(git symbolic-ref --quiet --short HEAD)" || die "Timetrack must be on a branch, not a detached HEAD."
if [[ -n "$(git status --porcelain)" ]]; then
	die "Timetrack working tree must be clean before publishing."
fi

case "$current_branch" in
main)
	publish_profile=".NET 10 production"
	expected_target_framework="net10.0"
	publisher="$script_dir/publish-tt-net10.sh"
	image_tag="v2"
	allow_production_tag="true"
	;;
development)
	publish_profile=".NET 10 development trial"
	expected_target_framework="net10.0"
	publisher="$script_dir/publish-tt-net10.sh"
	image_tag="net10-trial"
	allow_production_tag="false"
	;;
release/1.0.91)
	publish_profile="frozen .NET 8 production rollback"
	expected_target_framework="net8.0"
	publisher="$script_dir/publish-tt-net8.sh"
	image_tag="v2"
	allow_production_tag="true"
	;;
*)
	die "Publishing is not configured for branch '$current_branch'. Use main, development, or release/1.0.91."
	;;
esac

target_framework="$(sed -nE 's|.*<TargetFramework>([^<]+)</TargetFramework>.*|\1|p' "$csproj" | head -n 1)"
[[ "$target_framework" == "$expected_target_framework" ]] || die "Branch '$current_branch' requires TargetFramework '$expected_target_framework'; found '${target_framework:-none}'."
[[ -x "$publisher" ]] || die "Publisher is not executable: $publisher"

echo "Publishing TimeTrack profile: $publish_profile"
echo "Source branch: $current_branch"
echo "Target framework: $target_framework"
echo "Image tag: portainer.ardis.eu:5000/ardis-timetrack:$image_tag"

export TIMETRACK_ALLOW_PRODUCTION_TAG="$allow_production_tag"
exec "$publisher" "$timetrack_root" "$image_tag"
