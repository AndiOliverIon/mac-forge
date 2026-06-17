#!/usr/bin/env bash
set -euo pipefail

die() {
	echo "Error: $*" >&2
	exit 1
}

TOOLS_EXT_ROOT="${TOOLS_EXT_ROOT:-$HOME/work/ardis.tools.extensions}"
PUBLISH_DIR="$TOOLS_EXT_ROOT/Ardis.Utils/bin/Release/net8.0/linux-x64/publish"

[[ -d "$TOOLS_EXT_ROOT" ]] || die "Tools Extensions repo not found: $TOOLS_EXT_ROOT"

cd "$TOOLS_EXT_ROOT"

[[ -x ./buildsolution.sh ]] || die "Solution build script is not executable: $TOOLS_EXT_ROOT/buildsolution.sh"
[[ -f ./Ardis.Utils/build-docker.sh ]] || die "Docker build script is missing: $TOOLS_EXT_ROOT/Ardis.Utils/build-docker.sh"

echo "Running Tools Extensions solution build..."
./buildsolution.sh

[[ -f "$PUBLISH_DIR/build-docker.sh" ]] || die "Published Docker build script is missing: $PUBLISH_DIR/build-docker.sh"

echo "Running Tools Extensions Docker build and push..."
bash "$PUBLISH_DIR/build-docker.sh"
