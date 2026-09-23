#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJDIR="$ROOT/Ardis.Timetrack"
OUTDIR="$ROOT/ardis.timetrack.client/src/app/shared/api"
OUTFILE="$OUTDIR/TimetrackApiClient.ts"

cd "$ROOT"
dotnet tool restore

dotnet build "$PROJDIR/Ardis.Timetrack.csproj" -c Debug

# Generate OpenAPI JSON from the built assembly.
TARGET_FRAMEWORK="$(dotnet msbuild "$PROJDIR/Ardis.Timetrack.csproj" -nologo -getProperty:TargetFramework | tr -d '\r' | tail -n 1)"
if [[ ! "$TARGET_FRAMEWORK" =~ ^net[0-9]+\.[0-9]+$ ]]; then
	echo "Unable to determine TargetFramework for $PROJDIR/Ardis.Timetrack.csproj" >&2
	exit 1
fi
DLL="$PROJDIR/bin/Debug/$TARGET_FRAMEWORK/Ardis.Timetrack.dll"
dotnet tool run swagger tofile --output "$PROJDIR/openapi-v1.json" "$DLL" v1

# Ensure output directory exists; optionally force regeneration.
mkdir -p "$OUTDIR"
rm -f "$OUTFILE"

# Generate TS client (run from repo root).
dotnet tool run nswag run "$ROOT/nswag.json" /variables:ProjectDir="$PROJDIR/"

echo "OpenAPI: $PROJDIR/openapi-v1.json"
echo "TS client: $OUTFILE"
