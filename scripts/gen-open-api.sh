#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_NAME="Ardis.Perform"

if [[ $# -gt 1 ]]; then
    echo "Usage: genopenapi [--old]" >&2
    exit 1
fi

if [[ ${1:-} == "--old" ]]; then
    PROJECT_NAME="Asms2.Web"
elif [[ $# -eq 1 ]]; then
    echo "Usage: genopenapi [--old]" >&2
    exit 1
fi

PROJDIR="$ROOT/$PROJECT_NAME"
OUTDIR="$ROOT/ardis.perform.client/src/app/shared/api"
OUTFILE="$OUTDIR/PerformApiClient.ts"
TARGET_FRAMEWORK="$(dotnet msbuild "$PROJDIR/$PROJECT_NAME.csproj" -getProperty:TargetFramework -property:Configuration=Debug)"

if [[ -z "$TARGET_FRAMEWORK" ]]; then
    echo "Could not determine the target framework for $PROJDIR/$PROJECT_NAME.csproj" >&2
    exit 1
fi

cd "$ROOT"
dotnet tool restore

dotnet build "$PROJDIR/$PROJECT_NAME.csproj" -c Debug

# Generate OpenAPI JSON from the built assembly
DLL="$PROJDIR/bin/Debug/$TARGET_FRAMEWORK/osx-arm64/Ardis.Perform.dll"
dotnet tool run swagger tofile --output "$PROJDIR/openapi-v1.json" "$DLL" v1

# Ensure output directory exists; optionally force regeneration
mkdir -p "$OUTDIR"
rm -f "$OUTFILE"

# Generate TS client (run from repo root)
dotnet tool run nswag run "$ROOT/nswag.json" /variables:ProjectDir="$PROJDIR/"

echo "OpenAPI: $PROJDIR/openapi-v1.json"
echo "TS client: $OUTFILE"
