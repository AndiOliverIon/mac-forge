#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
	echo "Usage: publish-tt-net8.sh <timetrack-repository> <v2>" >&2
	exit 1
fi

timetrack_root="$1"
image_tag="$2"
publisher="$timetrack_root/Ardis.Timetrack/build-docker.sh"

if [[ "$image_tag" != "v2" ]]; then
	echo "Error: the frozen .NET 8 publisher supports only the v2 image tag." >&2
	exit 1
fi

if [[ ! -x "$publisher" ]]; then
	echo "Error: .NET 8 publisher is not executable: $publisher" >&2
	exit 1
fi

exec "$publisher"
