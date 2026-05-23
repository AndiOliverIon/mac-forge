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
DLL="$PROJDIR/bin/Debug/net8.0/Ardis.Timetrack.dll"
dotnet tool run swagger tofile --output "$PROJDIR/openapi-v1.json" "$DLL" v1

# Ensure output directory exists; optionally force regeneration.
mkdir -p "$OUTDIR"
rm -f "$OUTFILE"

# Generate TS client (run from repo root).
dotnet tool run nswag run "$ROOT/nswag.json" /variables:ProjectDir="$PROJDIR/"

echo "OpenAPI: $PROJDIR/openapi-v1.json"
echo "TS client: $OUTFILE"
