#!/usr/bin/env bash

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJDIR="${ROOT}/Asms2.Web"
OUTDIR="${ROOT}/ardis.perform.client/src/app/shared/api"
OUTFILE="${OUTDIR}/PerformApiClient.ts"
RUNTIME_ID="linux-x64"
LOCKFILE="${TMPDIR:-/tmp}/ardis-perform-genopenapi-packages.lock.json"
TARGET_FRAMEWORK="$(
    dotnet msbuild "${PROJDIR}/Asms2.Web.csproj" \
        -getProperty:TargetFramework \
        -property:Configuration=Debug
)"

if [[ -z "${TARGET_FRAMEWORK}" ]]; then
    echo "Could not determine the target framework for ${PROJDIR}/Asms2.Web.csproj" >&2
    exit 1
fi

cd "${ROOT}"
dotnet tool restore
dotnet restore "${PROJDIR}/Asms2.Web.csproj" \
    -r "${RUNTIME_ID}" \
    --disable-parallel \
    --verbosity normal \
    -m:1 \
    -p:BuildInParallel=false \
    -p:RestorePackagesWithLockFile=false \
    -p:NuGetLockFilePath="${LOCKFILE}"
dotnet build "${PROJDIR}/Asms2.Web.csproj" \
    -c Debug \
    -r "${RUNTIME_ID}" \
    -m:1 \
    -p:BuildInParallel=false \
    --no-restore

DLL="${PROJDIR}/bin/Debug/${TARGET_FRAMEWORK}/${RUNTIME_ID}/Ardis.Perform.dll"
if [[ ! -f "${DLL}" ]]; then
    echo "Built assembly not found: ${DLL}" >&2
    exit 1
fi

dotnet tool run swagger tofile \
    --output "${PROJDIR}/openapi-v1.json" \
    "${DLL}" \
    v1

mkdir -p "${OUTDIR}"
rm -f "${OUTFILE}"

dotnet tool run nswag run \
    "${ROOT}/nswag.json" \
    "/variables:ProjectDir=${PROJDIR}/"

echo "OpenAPI: ${PROJDIR}/openapi-v1.json"
echo "TS client: ${OUTFILE}"
