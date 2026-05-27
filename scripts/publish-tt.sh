#!/usr/bin/env bash
set -euo pipefail

die() {
	echo "Error: $*" >&2
	exit 1
}

TIMETRACK_ROOT="${TIMETRACK_ROOT:-$HOME/work/ardis.timetrack}"

[[ -d "$TIMETRACK_ROOT" ]] || die "Timetrack repo not found: $TIMETRACK_ROOT"

cd "$TIMETRACK_ROOT"

[[ -x ./buildsolution.sh ]] || die "Solution build script is not executable: $TIMETRACK_ROOT/buildsolution.sh"
[[ -x ./Ardis.Timetrack/build-docker.sh ]] || die "Docker build script is not executable: $TIMETRACK_ROOT/Ardis.Timetrack/build-docker.sh"

echo "Running Timetrack solution build..."
./buildsolution.sh

echo "Running Timetrack Docker build and push..."
./Ardis.Timetrack/build-docker.sh
