#!/usr/bin/env bash
set -euo pipefail

#######################################
# Local Portainer-style Perform publisher
#
# Builds a Linux container stack from the current Perform checkout without
# changing files in the application repository.
#######################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/forge.sh" ]]; then
	# shellcheck disable=SC1091
	source "$SCRIPT_DIR/forge.sh"
elif [[ -f "$HOME/mac-forge/scripts/forge.sh" ]]; then
	# shellcheck disable=SC1091
	source "$HOME/mac-forge/scripts/forge.sh"
fi

if [[ -n "${FORGE_SECRETS_FILE:-}" && -f "$FORGE_SECRETS_FILE" ]]; then
	# shellcheck disable=SC1091
	source "$FORGE_SECRETS_FILE"
fi

die() {
	echo "Error: $*" >&2
	exit 1
}

info() {
	echo "==> $*"
}

usage() {
	cat <<'EOF'
Usage:
  perform-local-portainer.sh [options]

Build the current Perform checkout into local Linux Docker images and generate
a Portainer-like compose stack for pre-merge verification.

Options:
  --repo PATH              Perform repository root. Defaults to current git root,
                           PERFORM_ROOT, or ~/work/ardis-perform-230.
  --interactive            Pick repo, branch, and database with fzf.
  --branch NAME            Branch/ref to publish. If it is the current branch,
                           the staged copy includes uncommitted working-tree edits.
                           Other refs are staged from git without checking out.
  --config-version VALUE   Config file version to use: 2.28, 2.30, dev, latest.
                           Defaults to release/x.y -> x.y, development -> dev.
  --tag TAG                Docker image tag. Defaults to branch + short SHA.
  --env-name NAME          Local environment suffix. Defaults to branch-safe tag.
  --stack-name NAME        Compose project/stack name. Defaults to perform-ENV.
  --work-dir PATH          Staging root. Defaults to ~/.local/share/perform-local-portainer.
  --host-folder PATH       Host data folder mounted as /hostdata.
  --db-server VALUE        SQL Server from containers. Defaults to host.docker.internal,FORGE_SQL_PORT.
  --db-name NAME           Database name. Required if DB_NAME is not set; default derives from env name.
  --db-user USER           Database user. Defaults to FORGE_SQL_USER or sa.
  --db-password PASSWORD   Database password. Defaults to FORGE_SQL_SA_PASSWORD or DB_PASSWORD.
  --license-server HOST    License server. Defaults to ARDIS_LICENSE_SERVER, CODEMETER_HOST, or host.docker.internal.
  --perform-port PORT      Host port for Perform. Defaults to 8080.
  --checklist-port PORT    Host port for Checklist. Defaults to 8300.
  --configuration NAME     dotnet publish configuration. Defaults to Debug.
  --skip-yarn              Skip yarn install/build in the staged source copy.
  --skip-publish           Reuse an existing staged Delivery folder.
  --skip-image-build       Generate compose but do not build Docker images.
  --compose-up             Run docker compose up after publishing.
  --detached               Use docker compose up -d with --compose-up.
  --with-setlicense        Add a Portainer-like setlicense one-shot service.
  --codemeter-deb PATH     Install CodeMeter from this .deb in the local base image.
  --download-codemeter     Download CodeMeter .deb into the staging folder before building.
  --help                   Show this help.

Examples:
  publish-perf-local
  perform-local-portainer.sh --repo ~/work/ardis-perform-230 --branch release/2.28 --config-version 2.28 --compose-up
  perform-local-portainer.sh --repo ~/work/ardis-perform --branch development --config-version dev --tag dashboard-candidate

Notes:
  - The Perform repository is read-only input for this script.
  - Build/publish commands run from a staged copy of the checkout.
  - Generated files live under the staging work-dir.
  - Default local stack uses HTTP to avoid needing the Portainer PFX locally.
EOF
}

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."
}

choose_with_fzf() {
	local prompt="$1"
	shift

	printf '%s\n' "$@" | fzf --prompt="$prompt" --height=12 --border
}

interactive_repo() {
	local selected

	selected="$(choose_with_fzf "Perform repo: " \
		"/Users/oliver/work/ardis-perform" \
		"/Users/oliver/work/ardis-perform-230")" || return 1

	[[ -n "$selected" ]] || return 1
	printf '%s\n' "$selected"
}

interactive_branch() {
	local selected

	selected="$(choose_with_fzf "Branch/ref: " \
		"release/2.28" \
		"release/2.30" \
		"development" \
		"custom")" || return 1

	[[ -n "$selected" ]] || return 1
	if [[ "$selected" == "custom" ]]; then
		read -r -p "Branch/ref: " selected
	fi

	[[ -n "$selected" ]] || return 1
	printf '%s\n' "$selected"
}

interactive_database() {
	local selected

	selected="$(choose_with_fzf "Database: " \
		"localhost" \
		"masterchief")" || return 1

	case "$selected" in
		localhost)
			DB_SERVER="host.docker.internal,2022"
			DB_NAME="ArdisDemo"
			DB_USER="sa"
			DB_PASSWORD="Open1147"
			;;
		masterchief)
			DB_SERVER="masterchief,2022"
			DB_NAME="ArdisDemo"
			DB_USER="sa"
			DB_PASSWORD="Open1147"
			;;
		*)
			return 1
			;;
	esac
}

slugify() {
	printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's#[^a-z0-9_.-]+#-#g; s#^-+##; s#-+$##'
}

detect_repo_root() {
	local candidate

	if git rev-parse --show-toplevel >/dev/null 2>&1; then
		candidate="$(git rev-parse --show-toplevel)"
		if [[ -f "$candidate/Asms2.Web/Asms2.Web.csproj" ]]; then
			printf '%s\n' "$candidate"
			return 0
		fi
	fi

	for candidate in "${PERFORM_ROOT:-}" "$HOME/work/ardis-perform-230" "$HOME/work/ardis-perform"; do
		[[ -n "$candidate" ]] || continue
		if [[ -f "$candidate/Asms2.Web/Asms2.Web.csproj" ]]; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done

	return 1
}

detect_target_framework() {
	local csproj="$1"
	local tfm tfms

	tfm="$(sed -n 's/.*<TargetFramework>\(.*\)<\/TargetFramework>.*/\1/p' "$csproj" | head -n1)"
	if [[ -n "$tfm" ]]; then
		printf '%s\n' "$tfm"
		return 0
	fi

	tfms="$(sed -n 's/.*<TargetFrameworks>\(.*\)<\/TargetFrameworks>.*/\1/p' "$csproj" | head -n1)"
	if [[ -n "$tfms" ]]; then
		printf '%s\n' "${tfms%%;*}"
		return 0
	fi

	return 1
}

infer_config_version() {
	local branch="$1"

	case "$branch" in
		release/*)
			printf '%s\n' "${branch#release/}"
			;;
		development | develop | dev)
			printf 'dev\n'
			;;
		*)
			printf 'latest\n'
			;;
	esac
}

find_config_file() {
	local repo="$1"
	local name="$2"
	local version="$3"

	if [[ -f "$repo/Docker/config/${name}-${version}.json" ]]; then
		printf '%s\n' "$repo/Docker/config/${name}-${version}.json"
		return 0
	fi

	return 1
}

copy_dir_contents() {
	local source="$1"
	local target="$2"

	mkdir -p "$target"
	if [[ -d "$source" ]]; then
		cp -R "$source"/. "$target"/
	fi
}

stage_source() {
	local source="$1"
	local target="$2"

	rm -rf "$target"
	mkdir -p "$target"

	rsync -a --delete \
		--exclude '.git/' \
		--exclude '.vs/' \
		--exclude '.idea/' \
		--exclude '.angular/cache/' \
		--exclude 'node_modules/' \
		--exclude 'bin/' \
		--exclude 'obj/' \
		"$source"/ "$target"/
}

stage_git_ref() {
	local repo="$1"
	local ref="$2"
	local target="$3"

	rm -rf "$target"
	mkdir -p "$target"

	git -C "$repo" archive --format=tar "$ref" | tar -xf - -C "$target"
}

write_runtime_files() {
	local runtime_dir="$1"
	local dotnet_major="$2"
	local codemeter_deb="$3"

	mkdir -p "$runtime_dir"

	cat >"$runtime_dir/Dockerfile-base" <<EOF
FROM mcr.microsoft.com/dotnet/aspnet:${dotnet_major}.0
WORKDIR /app

RUN apt-get update \\
    && apt-get install -y --no-install-recommends \\
        ca-certificates \\
        wget \\
        libgdiplus \\
        libicu-dev \\
        libharfbuzz0b \\
        libfontconfig1 \\
        libfreetype6 \\
        libpango-1.0-0 \\
        libpangocairo-1.0-0 \\
        procps \\
    && rm -rf /var/lib/apt/lists/*
EOF

	if [[ -n "$codemeter_deb" ]]; then
		cp -f "$codemeter_deb" "$runtime_dir/codemeter.latest.deb"
		cat >>"$runtime_dir/Dockerfile-base" <<'EOF'

COPY codemeter.latest.deb /tmp/codemeter.latest.deb
RUN apt-get update \
    && apt-get install -y /tmp/codemeter.latest.deb \
    && rm -f /tmp/codemeter.latest.deb \
    && rm -rf /var/lib/apt/lists/*
EOF
	fi

	cat >"$runtime_dir/Dockerfile-perform" <<'EOF'
ARG BASE_IMAGE
FROM ${BASE_IMAGE}
WORKDIR /app
EXPOSE 8080
COPY . ./
RUN chmod -R +rx /app
ENTRYPOINT ["/app/init_perform.sh"]
EOF

	cat >"$runtime_dir/Dockerfile-checklist" <<'EOF'
ARG BASE_IMAGE
FROM ${BASE_IMAGE}
WORKDIR /app/Checklist
EXPOSE 8300 22352 22350
COPY . ./
RUN chmod -R +rx /app
ENTRYPOINT ["/app/Checklist/init_checklist.sh"]
EOF

	cat >"$runtime_dir/Dockerfile-migrations" <<'EOF'
ARG BASE_IMAGE
FROM ${BASE_IMAGE}
WORKDIR /app/Migrations
COPY . ./
RUN chmod -R +rx /app
ENTRYPOINT ["/app/Migrations/launch_migrations.sh"]
EOF

	cat >"$runtime_dir/init_perform.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${ARDIS_LICENSE_SERVER:-}" && -x /usr/sbin/CodeMeterLin ]]; then
	echo "Using license server: ${ARDIS_LICENSE_SERVER}"
	if [[ -f /etc/wibu/CodeMeter/Server.ini ]]; then
		sed -i 's/Address=255.255.255.255/Address='"${ARDIS_LICENSE_SERVER}"'/g' /etc/wibu/CodeMeter/Server.ini || true
	fi
	/usr/sbin/CodeMeterLin -L+ &
fi

echo "Starting PERFORM service"
if [[ -x /app/Ardis.Perform ]]; then
	exec /app/Ardis.Perform --urls "${ASPNETCORE_URLS:-http://+:8080}"
fi

exec dotnet /app/Ardis.Perform.dll --urls "${ASPNETCORE_URLS:-http://+:8080}"
EOF

	cat >"$runtime_dir/init_checklist.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${ARDIS_LICENSE_SERVER:-}" && -x /usr/sbin/CodeMeterLin ]]; then
	echo "Using license server: ${ARDIS_LICENSE_SERVER}"
	if [[ -f /etc/wibu/CodeMeter/Server.ini ]]; then
		sed -i 's/Address=255.255.255.255/Address='"${ARDIS_LICENSE_SERVER}"'/g' /etc/wibu/CodeMeter/Server.ini || true
	fi
	/usr/sbin/CodeMeterLin -L+ &
fi

echo "Starting Checklist service"
if [[ -x /app/Checklist/Ardis.Checklist.Worker ]]; then
	exec /app/Checklist/Ardis.Checklist.Worker --urls "${ASPNETCORE_URLS:-http://+:8300}"
fi

exec dotnet /app/Checklist/Ardis.Checklist.Worker.dll --urls "${ASPNETCORE_URLS:-http://+:8300}"
EOF

	cat >"$runtime_dir/launch_migrations.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "Starting Perform Migration Tool (in Docker)"
mkdir -p /hostdata/Migrations
cp -Rf /app/Migrations/. /hostdata/Migrations/
timestamp="$(date +%Y%m%d_%H%M%S)"

if [[ -x /app/Migrations/Ardis.Migrations.Console ]]; then
	/app/Migrations/Ardis.Migrations.Console -v -logs -demo \
		1>"/hostdata/Migrations/migration-${timestamp}.log" \
		2>"/hostdata/Migrations/migration-${timestamp}.err"
else
	dotnet /app/Migrations/Ardis.Migrations.Console.dll -v -logs -demo \
		1>"/hostdata/Migrations/migration-${timestamp}.log" \
		2>"/hostdata/Migrations/migration-${timestamp}.err"
fi
EOF

	chmod +x "$runtime_dir/init_perform.sh" "$runtime_dir/init_checklist.sh" "$runtime_dir/launch_migrations.sh"
}

write_setlicense_script() {
	local runtime_dir="$1"

	cat >"$runtime_dir/setlicense.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SQLCMD="/opt/mssql-tools18/bin/sqlcmd"
if [[ ! -x "$SQLCMD" ]]; then
	SQLCMD="/opt/mssql-tools/bin/sqlcmd"
fi

[[ -x "$SQLCMD" ]] || {
	echo "sqlcmd not found in container" >&2
	exit 1
}

: "${SQL_SERVER:?SQL_SERVER is required}"
: "${SQL_DATABASE:?SQL_DATABASE is required}"
: "${SA_USER:?SA_USER is required}"
: "${SA_PASSWORD:?SA_PASSWORD is required}"
: "${LICENSE_FILE:?LICENSE_FILE is required}"
: "${LICENSE_NAME:?LICENSE_NAME is required}"

echo "Updating license setting in ${SQL_DATABASE} on ${SQL_SERVER}"
"$SQLCMD" -S "$SQL_SERVER" -U "$SA_USER" -P "$SA_PASSWORD" -C -b -Q \
	"use [$SQL_DATABASE]; update system.Setting set value = '{\"File\":\"$LICENSE_FILE\",\"Name\":\"$LICENSE_NAME\"}' where category = 'License' and name = 'info'"
EOF

	chmod +x "$runtime_dir/setlicense.sh"
}

write_compose_file() {
	local compose_file="$1"
	local with_setlicense="$2"

	cat >"$compose_file" <<'EOF'
version: "3.9"

networks:
  performnetwork:
    name: ${NETWORK_NAME}

services:
EOF

	if [[ "$with_setlicense" == "true" ]]; then
		cat >>"$compose_file" <<'EOF'
  setlicense:
    image: mcr.microsoft.com/mssql/server:2019-latest
    networks:
      - performnetwork
    extra_hosts:
      - "host.docker.internal:host-gateway"
    environment:
      SA_USER: "${DB_USER}"
      SA_PASSWORD: "${DB_PASSWORD}"
      SQL_SERVER: "${DB_DOCKER_SERVER}"
      ACCEPT_EULA: "Y"
      SQL_DATABASE: "${DB_NAME}"
      LICENSE_FILE: "${LICENSE_FILE}"
      LICENSE_NAME: "${LICENSE_NAME}"
      ENVNAME: "${ENVNAME}"
      TZ: "${TIMEZONE}"
    hostname: setlicense_${ENVNAME}
    container_name: setlicenseContainer_${ENVNAME}
    volumes:
      - ${HOST_FOLDER}:/hostdata
      - ${RUNTIME_DIR}/setlicense.sh:/setlicense.sh:ro
    command: bash -c "/setlicense.sh"

EOF
	fi

	cat >>"$compose_file" <<'EOF'
  migrations:
    image: "${MIGRATIONS_IMAGE}"
    networks:
      - performnetwork
    extra_hosts:
      - "host.docker.internal:host-gateway"
    environment:
      MIGRATIONS_DatabaseConnectionString: "Server=${DB_DOCKER_SERVER};Database=${DB_NAME};User Id=${DB_USER};Password=${DB_PASSWORD};MultipleActiveResultSets=True;TrustServerCertificate=true;Encrypt=false"
      MIGRATIONS_WithDataSourceValidation: "false"
      TZ: "${TIMEZONE}"
    hostname: migration_${ENVNAME}
    container_name: migrationContainer_${ENVNAME}
    volumes:
      - ${HOST_FOLDER}:/hostdata
      - ${RUNTIME_DIR}:/srv
EOF

	if [[ "$with_setlicense" == "true" ]]; then
		cat >>"$compose_file" <<'EOF'
    depends_on:
      setlicense:
        condition: service_completed_successfully
EOF
	fi

	cat >>"$compose_file" <<'EOF'

  checklist:
    image: "${CHECKLIST_IMAGE}"
    networks:
      - performnetwork
    extra_hosts:
      - "host.docker.internal:host-gateway"
    ports:
      - "${CHECKLIST_PORT}:8300"
    environment:
      CHECKLIST_DatabaseConnectionString: "Server=${DB_DOCKER_SERVER};Database=${DB_NAME};User Id=${DB_USER};Password=${DB_PASSWORD};MultipleActiveResultSets=True;TrustServerCertificate=true;Encrypt=false"
      CHECKLIST_ApiUrl: "http://localhost:${CHECKLIST_PORT}"
      CODEMETER_HOST: "${LICENSE_SERVER}"
      ARDIS_LICENSE_SERVER: "${LICENSE_SERVER}"
      LICENSE_SERVER: "${LICENSE_SERVER}"
      TZ: "${TIMEZONE}"
      ASPNETCORE_URLS: "http://+:8300"
      PERFORM_ExternalFolder: "/hostdata/"
    hostname: checklist_${ENVNAME}
    container_name: checklistContainer_${ENVNAME}
    restart: unless-stopped
    volumes:
      - ${HOST_FOLDER}:/hostdata
      - ${RUNTIME_DIR}:/srv
    depends_on:
      migrations:
        condition: service_completed_successfully
    healthcheck:
      test: wget --spider --no-verbose http://localhost:8300/health || exit 1
      interval: 10s
      timeout: 3s
      retries: 10

  perform:
    image: "${PERFORM_IMAGE}"
    networks:
      - performnetwork
    extra_hosts:
      - "host.docker.internal:host-gateway"
    ports:
      - "${PERFORM_PORT}:8080"
    environment:
      PERFORM_DatabaseConnectionString: "Server=${DB_DOCKER_SERVER};Database=${DB_NAME};User Id=${DB_USER};Password=${DB_PASSWORD};Min Pool Size=10; Max Pool Size=100;MultipleActiveResultSets=True;Connection Timeout=600;TrustServerCertificate=true;Encrypt=false"
      PERFORM_PlanningEndpoint: "http://host.docker.internal:${PERFORM_PORT}/Planning/"
      PERFORM_ChecklistEndpoint: "http://host.docker.internal:${CHECKLIST_PORT}/"
      CODEMETER_HOST: "${LICENSE_SERVER}"
      ARDIS_LICENSE_SERVER: "${LICENSE_SERVER}"
      LICENSE_SERVER: "${LICENSE_SERVER}"
      TZ: "${TIMEZONE}"
      ASPNETCORE_URLS: "http://+:8080"
      PERFORM_ExternalFolder: "/hostdata/"
    hostname: perform_${ENVNAME}
    container_name: performContainer_${ENVNAME}
    restart: unless-stopped
    volumes:
      - ${HOST_FOLDER}:/hostdata
      - ${RUNTIME_DIR}:/srv
    stdin_open: true
    tty: true
    depends_on:
      checklist:
        condition: service_healthy
    healthcheck:
      test: wget --spider --no-verbose http://localhost:8080/health || exit 1
      interval: 10s
      timeout: 3s
      retries: 10
EOF
}

write_env_file() {
	local env_file="$1"

	cat >"$env_file" <<EOF
ENVNAME=${ENV_NAME}
NETWORK_NAME=${NETWORK_NAME}
HOST_FOLDER=${HOST_FOLDER}
RUNTIME_DIR=${RUNTIME_DIR}
DB_DOCKER_SERVER=${DB_SERVER}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
LICENSE_SERVER=${LICENSE_SERVER}
LICENSE_FILE=${LICENSE_FILE}
LICENSE_NAME=${LICENSE_NAME}
TIMEZONE=${TIMEZONE}
PERFORM_PORT=${PERFORM_PORT}
CHECKLIST_PORT=${CHECKLIST_PORT}
PERFORM_IMAGE=${PERFORM_IMAGE}
CHECKLIST_IMAGE=${CHECKLIST_IMAGE}
MIGRATIONS_IMAGE=${MIGRATIONS_IMAGE}
EOF
}

publish_delivery() {
	local repo="$1"
	local delivery="$2"
	local config_version="$3"
	local configuration="$4"
	local tfm="$5"
	local skip_yarn="$6"

	local publish_root="$delivery/.publish"
	local perform_publish="$publish_root/perform"
	local checklist_publish="$publish_root/checklist"
	local migrations_publish="$publish_root/migrations"
	local perform_config checklist_config

	rm -rf "$delivery"
	mkdir -p "$perform_publish" "$checklist_publish" "$migrations_publish"

	if [[ "$skip_yarn" != "true" ]]; then
		info "Installing/building web assets with yarn"
		(
			cd "$repo"
			yarn --frozen-lockfile
			cd "$repo/Asms2.Web"
			yarn run build
		)
	fi

	info "Publishing Perform, Checklist, and Migrations for linux-x64"
	dotnet publish "$repo/Ardis.Migrations.Console/Ardis.Migrations.Console.csproj" \
		-o "$migrations_publish" --framework "$tfm" --self-contained false -r linux-x64 \
		--configuration "$configuration"
	dotnet publish "$repo/Ardis.Checklist.Worker/Ardis.Checklist.Worker.csproj" \
		-o "$checklist_publish" --framework "$tfm" --self-contained false -r linux-x64 \
		--configuration "$configuration"
	dotnet publish "$repo/Asms2.Web/Asms2.Web.csproj" \
		-o "$perform_publish" --framework "$tfm" --self-contained false -r linux-x64 \
		--configuration "$configuration"

	copy_dir_contents "$perform_publish" "$delivery"
	copy_dir_contents "$checklist_publish" "$delivery/Checklist"
	copy_dir_contents "$migrations_publish" "$delivery/Migrations"

	if [[ -d "$repo/Asms2.Web/wwwroot" ]]; then
		copy_dir_contents "$repo/Asms2.Web/wwwroot" "$delivery/wwwroot"
	fi

	perform_config="$(find_config_file "$repo" "appsettings-linux" "$config_version")" ||
		die "Could not find appsettings-linux-${config_version}.json under $repo/Docker/config. Pass --config-version with an existing config."
	checklist_config="$(find_config_file "$repo" "appsettings-linux-checklist" "$config_version")" ||
		die "Could not find appsettings-linux-checklist-${config_version}.json under $repo/Docker/config. Pass --config-version with an existing config."

	cp -f "$perform_config" "$delivery/appsettings.json"
	cp -f "$perform_config" "$delivery/Migrations/appsettings.json"
	cp -f "$checklist_config" "$delivery/Checklist/appsettings.json"
	cp -f "$RUNTIME_DIR/init_perform.sh" "$delivery/init_perform.sh"
	cp -f "$RUNTIME_DIR/init_checklist.sh" "$delivery/Checklist/init_checklist.sh"
	cp -f "$RUNTIME_DIR/launch_migrations.sh" "$delivery/Migrations/launch_migrations.sh"
}

build_images() {
	local runtime_dir="$1"
	local delivery="$2"
	local base_image="$3"

	info "Building local base image: $base_image"
	docker build "$runtime_dir" -t "$base_image" -f "$runtime_dir/Dockerfile-base"

	info "Building Perform image: $PERFORM_IMAGE"
	docker build "$delivery" -t "$PERFORM_IMAGE" -f "$runtime_dir/Dockerfile-perform" \
		--build-arg "BASE_IMAGE=$base_image"

	info "Building Checklist image: $CHECKLIST_IMAGE"
	docker build "$delivery/Checklist" -t "$CHECKLIST_IMAGE" -f "$runtime_dir/Dockerfile-checklist" \
		--build-arg "BASE_IMAGE=$base_image"

	info "Building Migrations image: $MIGRATIONS_IMAGE"
	docker build "$delivery/Migrations" -t "$MIGRATIONS_IMAGE" -f "$runtime_dir/Dockerfile-migrations" \
		--build-arg "BASE_IMAGE=$base_image"
}

REPO=""
EXPECTED_BRANCH=""
INTERACTIVE="false"
CONFIG_VERSION=""
TAG=""
ENV_NAME=""
STACK_NAME=""
WORK_DIR="${PERFORM_LOCAL_PORTAINER_ROOT:-$HOME/.local/share/perform-local-portainer}"
HOST_FOLDER=""
DB_SERVER=""
DB_NAME="${DB_NAME:-}"
DB_USER="${FORGE_SQL_USER:-${DB_USER:-sa}}"
DB_PASSWORD="${FORGE_SQL_SA_PASSWORD:-${DB_PASSWORD:-}}"
LICENSE_SERVER="${ARDIS_LICENSE_SERVER:-${CODEMETER_HOST:-host.docker.internal}}"
LICENSE_FILE="${LICENSE_FILE:-local.alx}"
LICENSE_NAME="${LICENSE_NAME:-PERFORM}"
TIMEZONE="${TIMEZONE:-Europe/Brussels}"
PERFORM_PORT="${PERFORM_PORT:-8080}"
CHECKLIST_PORT="${CHECKLIST_PORT:-8300}"
CONFIGURATION="${CONFIGURATION:-Debug}"
SKIP_YARN="false"
SKIP_PUBLISH="false"
SKIP_IMAGE_BUILD="false"
COMPOSE_UP="false"
DETACHED="false"
WITH_SETLICENSE="false"
CODEMETER_DEB=""
DOWNLOAD_CODEMETER="false"

while (($#)); do
	case "$1" in
		--interactive)
			INTERACTIVE="true"
			shift
			;;
		--repo)
			REPO="$2"
			shift 2
			;;
		--branch)
			EXPECTED_BRANCH="$2"
			shift 2
			;;
		--config-version)
			CONFIG_VERSION="$2"
			shift 2
			;;
		--tag)
			TAG="$2"
			shift 2
			;;
		--env-name)
			ENV_NAME="$(slugify "$2")"
			shift 2
			;;
		--stack-name)
			STACK_NAME="$(slugify "$2")"
			shift 2
			;;
		--work-dir)
			WORK_DIR="$2"
			shift 2
			;;
		--host-folder)
			HOST_FOLDER="$2"
			shift 2
			;;
		--db-server)
			DB_SERVER="$2"
			shift 2
			;;
		--db-name)
			DB_NAME="$2"
			shift 2
			;;
		--db-user)
			DB_USER="$2"
			shift 2
			;;
		--db-password)
			DB_PASSWORD="$2"
			shift 2
			;;
		--license-server)
			LICENSE_SERVER="$2"
			shift 2
			;;
		--perform-port)
			PERFORM_PORT="$2"
			shift 2
			;;
		--checklist-port)
			CHECKLIST_PORT="$2"
			shift 2
			;;
		--configuration)
			CONFIGURATION="$2"
			shift 2
			;;
		--skip-yarn)
			SKIP_YARN="true"
			shift
			;;
		--skip-publish)
			SKIP_PUBLISH="true"
			shift
			;;
		--skip-image-build)
			SKIP_IMAGE_BUILD="true"
			shift
			;;
		--compose-up)
			COMPOSE_UP="true"
			shift
			;;
		--detached)
			DETACHED="true"
			shift
			;;
		--with-setlicense)
			WITH_SETLICENSE="true"
			shift
			;;
		--codemeter-deb)
			CODEMETER_DEB="$2"
			shift 2
			;;
		--download-codemeter)
			DOWNLOAD_CODEMETER="true"
			shift
			;;
		--help | -h)
			usage
			exit 0
			;;
		*)
			die "Unknown argument: $1"
			;;
	esac
done

require_cmd git
require_cmd dotnet
require_cmd docker
require_cmd rsync

if [[ "$SKIP_YARN" != "true" ]]; then
	require_cmd yarn
fi

if [[ "$INTERACTIVE" == "true" ]]; then
	require_cmd fzf

	if [[ -z "$REPO" ]]; then
		REPO="$(interactive_repo)" || die "No Perform repo selected."
	fi

	if [[ -z "$EXPECTED_BRANCH" ]]; then
		EXPECTED_BRANCH="$(interactive_branch)" || die "No branch/ref selected."
	fi

	interactive_database || die "No database selected."
fi

if [[ -z "$REPO" ]]; then
	REPO="$(detect_repo_root)" || die "Could not detect Perform repo. Pass --repo PATH."
fi

[[ -f "$REPO/Asms2.Web/Asms2.Web.csproj" ]] || die "Not a Perform repo: $REPO"

REPO="$(cd "$REPO" && pwd)"
CURRENT_BRANCH="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
SHORT_SHA="$(git -C "$REPO" rev-parse --short HEAD)"
SOURCE_REF=""
SOURCE_LABEL="$CURRENT_BRANCH"
SOURCE_SHA="$SHORT_SHA"
STAGE_FROM_REF="false"

if [[ -n "$EXPECTED_BRANCH" ]]; then
	git -C "$REPO" rev-parse --verify "${EXPECTED_BRANCH}^{commit}" >/dev/null 2>&1 ||
		die "Branch/ref not found in repo: $EXPECTED_BRANCH"

	SOURCE_REF="$EXPECTED_BRANCH"
	SOURCE_LABEL="$EXPECTED_BRANCH"
	SOURCE_SHA="$(git -C "$REPO" rev-parse --short "$EXPECTED_BRANCH")"

	if [[ "$CURRENT_BRANCH" != "$EXPECTED_BRANCH" ]]; then
		STAGE_FROM_REF="true"
	fi
fi

if [[ -z "$CONFIG_VERSION" ]]; then
	CONFIG_VERSION="$(infer_config_version "$SOURCE_LABEL")"
fi

if [[ -z "$TAG" ]]; then
	TAG="$(slugify "${SOURCE_LABEL}-${SOURCE_SHA}")"
fi

if [[ -z "$ENV_NAME" ]]; then
	ENV_NAME="$(slugify "$TAG")"
fi

if [[ -z "$STACK_NAME" ]]; then
	STACK_NAME="perform-${ENV_NAME}"
fi

if [[ -z "$DB_SERVER" ]]; then
	DB_SERVER="host.docker.internal,${FORGE_SQL_PORT:-2022}"
fi

if [[ -z "$DB_NAME" ]]; then
	DB_NAME="perform_${ENV_NAME//-/_}"
fi

[[ -n "$DB_PASSWORD" ]] || die "DB password is required. Set FORGE_SQL_SA_PASSWORD, DB_PASSWORD, or pass --db-password."

ARTIFACT_ROOT="$WORK_DIR/$ENV_NAME"
STAGED_REPO="$ARTIFACT_ROOT/source"
RUNTIME_DIR="$ARTIFACT_ROOT/runtime"
DELIVERY_DIR="$ARTIFACT_ROOT/Delivery"
COMPOSE_FILE="$ARTIFACT_ROOT/docker-compose.yml"
ENV_FILE="$ARTIFACT_ROOT/.env"
HOST_FOLDER="${HOST_FOLDER:-$ARTIFACT_ROOT/hostdata}"
NETWORK_NAME="performnetwork_${ENV_NAME}"

BASE_IMAGE="ardis-perform-local-base:${TAG}"
PERFORM_IMAGE="ardis-perform-app:${TAG}"
CHECKLIST_IMAGE="ardis-perform-checklist:${TAG}"
MIGRATIONS_IMAGE="ardis-perform-migrations:${TAG}"

mkdir -p "$ARTIFACT_ROOT" "$HOST_FOLDER"

if [[ "$STAGE_FROM_REF" == "true" ]]; then
	git -C "$REPO" show "$SOURCE_REF:Asms2.Web/Asms2.Web.csproj" >"$ARTIFACT_ROOT/Asms2.Web.csproj"
	TFM="$(detect_target_framework "$ARTIFACT_ROOT/Asms2.Web.csproj")" || die "Could not detect TargetFramework from $SOURCE_REF."
else
	TFM="$(detect_target_framework "$REPO/Asms2.Web/Asms2.Web.csproj")" || die "Could not detect TargetFramework."
fi

DOTNET_MAJOR="${TFM#net}"
DOTNET_MAJOR="${DOTNET_MAJOR%%.*}"
[[ "$DOTNET_MAJOR" =~ ^[0-9]+$ ]] || die "Unsupported TargetFramework: $TFM"

if [[ "$DOWNLOAD_CODEMETER" == "true" ]]; then
	require_cmd curl
	CODEMETER_DEB="$ARTIFACT_ROOT/codemeter.latest.deb"
	info "Downloading CodeMeter package"
	curl -fsSL "https://download.ardis.be/tools/codemeter_7.51.5429.500_amd64.deb" -o "$CODEMETER_DEB"
fi

if [[ -n "$CODEMETER_DEB" && ! -f "$CODEMETER_DEB" ]]; then
	die "CodeMeter package not found: $CODEMETER_DEB"
fi

info "Repo: $REPO"
info "Current checkout: $CURRENT_BRANCH ($SHORT_SHA)"
info "Publishing source: $SOURCE_LABEL ($SOURCE_SHA)"
if [[ "$STAGE_FROM_REF" == "true" ]]; then
	info "Source mode: git archive of selected ref; Perform checkout will not be switched"
else
	info "Source mode: staged copy of current working tree"
fi
info "Target framework: $TFM"
info "Config version: $CONFIG_VERSION"
info "Image tag: $TAG"
info "Staging: $ARTIFACT_ROOT"

write_runtime_files "$RUNTIME_DIR" "$DOTNET_MAJOR" "$CODEMETER_DEB"
if [[ "$WITH_SETLICENSE" == "true" ]]; then
	write_setlicense_script "$RUNTIME_DIR"
fi

if [[ "$SKIP_PUBLISH" != "true" ]]; then
	info "Copying checkout to staged source: $STAGED_REPO"
	if [[ "$STAGE_FROM_REF" == "true" ]]; then
		stage_git_ref "$REPO" "$SOURCE_REF" "$STAGED_REPO"
	else
		stage_source "$REPO" "$STAGED_REPO"
	fi
	publish_delivery "$STAGED_REPO" "$DELIVERY_DIR" "$CONFIG_VERSION" "$CONFIGURATION" "$TFM" "$SKIP_YARN"
else
	[[ -d "$DELIVERY_DIR" ]] || die "--skip-publish requested, but Delivery does not exist: $DELIVERY_DIR"
fi

write_compose_file "$COMPOSE_FILE" "$WITH_SETLICENSE"
write_env_file "$ENV_FILE"

if [[ "$SKIP_IMAGE_BUILD" != "true" ]]; then
	build_images "$RUNTIME_DIR" "$DELIVERY_DIR" "$BASE_IMAGE"
fi

info "Compose file: $COMPOSE_FILE"
info "Env file: $ENV_FILE"
info "Perform URL: http://localhost:${PERFORM_PORT}"
info "Checklist URL: http://localhost:${CHECKLIST_PORT}"

if [[ "$COMPOSE_UP" == "true" ]]; then
	info "Starting compose stack: $STACK_NAME"
	if [[ "$DETACHED" == "true" ]]; then
		docker compose --project-name "$STACK_NAME" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d
	else
		docker compose --project-name "$STACK_NAME" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up
	fi
else
	cat <<EOF

Next:
  docker compose --project-name "$STACK_NAME" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up

Or detached:
  docker compose --project-name "$STACK_NAME" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d

Stop/remove:
  docker compose --project-name "$STACK_NAME" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" down
EOF
fi
