#!/usr/bin/env bash
set -euo pipefail

die() {
	echo "Error: $*" >&2
	exit 1
}

if [[ $# -ne 2 ]]; then
	die "Usage: publish-tt-net10.sh <timetrack-repository> <v2|net10-trial>"
fi

timetrack_root="$1"
image_tag="$2"
registry="portainer.ardis.eu:5000"
image_name="$registry/ardis-timetrack:$image_tag"
image_platform="linux/amd64"
project_dir="$timetrack_root/Ardis.Timetrack"
csproj="$project_dir/Ardis.Timetrack.csproj"
dockerfile="$project_dir/Dockerfile"
npmrc_path="$project_dir/.npmrc"
angular_dir="$timetrack_root/ardis.timetrack.client"
angular_dist="$angular_dir/dist/client"
publish_dir="$project_dir/docker-publish"

case "$image_tag" in
v2)
	[[ "${TIMETRACK_ALLOW_PRODUCTION_TAG:-}" == "true" ]] || die "Publishing v2 requires TIMETRACK_ALLOW_PRODUCTION_TAG=true."
	;;
net10-trial) ;;
*) die "Unsupported .NET 10 image tag: $image_tag" ;;
esac

[[ -f "$csproj" ]] || die "Timetrack project not found: $csproj"
[[ -f "$dockerfile" ]] || die "Dockerfile not found: $dockerfile"
[[ -f "$npmrc_path" ]] || die "Missing npm credentials file: $npmrc_path"

app_version="$(sed -nE 's|.*<Version>([^<]+)</Version>.*|\1|p' "$csproj" | head -n 1)"
[[ -n "$app_version" ]] || die "Application version not found."

app_published_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
source_revision="$(git -C "$timetrack_root" rev-parse HEAD)"
source_revision_short="$(git -C "$timetrack_root" rev-parse --short=12 HEAD)"
candidate_tag="${image_tag}-${source_revision_short}-v${app_version}"
candidate_image_name="$registry/ardis-timetrack:$candidate_tag"

if docker manifest inspect --insecure "$candidate_image_name" >/dev/null 2>&1; then
	die "Refusing to overwrite existing candidate tag: $candidate_tag"
fi

echo "Building Angular frontend..."
(
	export NPM_CONFIG_USERCONFIG="$npmrc_path"
	cd "$angular_dir"
	npm ci
	npm run build
)

[[ -d "$angular_dist" ]] || die "Angular build output not found: $angular_dist"

cat >"$angular_dist/app-version.json" <<JSON
{
  "version": "$app_version",
  "publishedAt": "$app_published_at"
}
JSON

echo "Publishing backend (Release, linux-x64)..."
rm -rf "$publish_dir"
dotnet publish "$csproj" -c Release -r linux-x64 --self-contained false -o "$publish_dir"

[[ -f "$publish_dir/Ardis.Timetrack.dll" ]] || die "Published entry assembly not found: $publish_dir/Ardis.Timetrack.dll"
[[ ! -f "$publish_dir/appsettings.Development.json" ]] || die "Development settings must not be included in publish output."

if grep -Eqi '"ClientSecret"[[:space:]]*:[[:space:]]*"[^"]+"|Password=[^;"]+' "$publish_dir"/appsettings*.json; then
	die "A secret was detected in published application settings."
fi

wwwroot_dir="$publish_dir/wwwroot"
mkdir -p "$wwwroot_dir"
cp -R "$angular_dist"/. "$wwwroot_dir"/
printf '%s' "$app_version" >"$wwwroot_dir/app-version.txt"
printf '%s' "$app_published_at" >"$wwwroot_dir/app-published-at.txt"

echo "Building Docker image ($image_platform) from verified .NET 10 publish output..."
docker build \
	"$publish_dir" \
	--pull \
	--platform "$image_platform" \
	--file "$dockerfile" \
	--label "org.opencontainers.image.created=$app_published_at" \
	--label "org.opencontainers.image.revision=$source_revision" \
	--label "org.opencontainers.image.version=$app_version" \
	--tag "$image_name" \
	--tag "$candidate_image_name"

echo "Pushing traceable candidate image..."
docker push "$candidate_image_name"

echo "Updating deployment image tag..."
docker push "$image_name"

echo "Done. Image: $image_name"
echo "Traceable candidate: $candidate_image_name"
echo "Version: $app_version"
echo "Published at: $app_published_at"
