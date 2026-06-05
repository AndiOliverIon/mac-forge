#!/usr/bin/env bash
set -euo pipefail

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
  deploy-wonderkitchen.sh [options]

Deploy the generated WonderKitchen static catalog to vps1.

By default this script runs in dry-run mode. Pass --apply to upload and switch
the live release.

Options:
  --source PATH       Static payload folder. Defaults to the current generated
                      WonderKitchen Static folder from alice-in-wonder-kitchen.
  --host HOST         SSH host. Defaults to vps1.
  --remote PATH       Remote app root. Defaults to /srv/tnisoft/wonderkitchen.
  --release NAME      Release folder name. Defaults to timestamp.
  --apply             Perform the upload and live switch.
  --keep N            Keep this many old releases after --apply. Defaults to 3.
  --help              Show this help.

Examples:
  deploy-wonderkitchen.sh
  deploy-wonderkitchen.sh --apply
  deploy-wonderkitchen.sh --source "$HOME/projects/alice-in-wonder-kitchen/WonderKitchen Static" --apply
EOF
}

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."
}

SOURCE="${WONDERKITCHEN_SOURCE:-$HOME/projects/alice-in-wonder-kitchen/WonderKitchen Static}"
HOST="${WONDERKITCHEN_HOST:-vps1}"
REMOTE_ROOT="${WONDERKITCHEN_REMOTE_ROOT:-/srv/tnisoft/wonderkitchen}"
RELEASE="$(date +%Y%m%d%H%M%S)"
APPLY=0
KEEP=3

while (($#)); do
	case "$1" in
		--source)
			[[ $# -ge 2 ]] || die "--source requires a path."
			SOURCE="$2"
			shift 2
			;;
		--host)
			[[ $# -ge 2 ]] || die "--host requires a host."
			HOST="$2"
			shift 2
			;;
		--remote)
			[[ $# -ge 2 ]] || die "--remote requires a path."
			REMOTE_ROOT="$2"
			shift 2
			;;
		--release)
			[[ $# -ge 2 ]] || die "--release requires a name."
			RELEASE="$2"
			shift 2
			;;
		--apply)
			APPLY=1
			shift
			;;
		--keep)
			[[ $# -ge 2 ]] || die "--keep requires a number."
			KEEP="$2"
			shift 2
			;;
		--help|-h)
			usage
			exit 0
			;;
		*)
			die "Unknown option: $1"
			;;
	esac
done

[[ "$KEEP" =~ ^[0-9]+$ ]] || die "--keep must be a number."
[[ -d "$SOURCE" ]] || die "Source folder not found: $SOURCE"

require_cmd ssh
require_cmd rsync
require_cmd curl

if ! ssh "$HOST" "command -v rsync >/dev/null 2>&1"; then
	die "Remote host '$HOST' does not have rsync installed. Run on vps1: sudo apt install -y rsync"
fi

for required_path in \
	"manifest.json" \
	"catalogs/ro/manifest.json" \
	"catalogs/ro/recipes.json" \
	"catalogs/ro/categories.json" \
	"catalogs/en/manifest.json" \
	"catalogs/en/recipes.json" \
	"catalogs/en/categories.json" \
	"images_manifest.json" \
	"images/index.json"; do
	[[ -f "$SOURCE/$required_path" ]] || die "Missing required payload file: $required_path"
done

REMOTE_RELEASES="$REMOTE_ROOT/releases"
REMOTE_RELEASE="$REMOTE_RELEASES/$RELEASE"
REMOTE_CURRENT="$REMOTE_ROOT/public"

info "Source: $SOURCE"
info "Target: $HOST:$REMOTE_RELEASE"
if [[ "$APPLY" -eq 0 ]]; then
	info "Mode: dry-run. Pass --apply to deploy."
else
	info "Mode: apply"
fi

if [[ "$APPLY" -eq 1 ]]; then
	ssh "$HOST" "mkdir -p '$REMOTE_RELEASES'"
fi

REMOTE_BASIS="$(ssh "$HOST" "if [ -e '$REMOTE_CURRENT' ]; then readlink -f '$REMOTE_CURRENT'; fi")"
if [[ -n "$REMOTE_BASIS" ]]; then
	info "Basis: $HOST:$REMOTE_BASIS"
fi

RSYNC_ARGS=(
	-az
	--checksum
	--itemize-changes
	--delete
	--exclude ".DS_Store"
	--exclude "._*"
)

if [[ -n "$REMOTE_BASIS" ]]; then
	RSYNC_ARGS+=(--link-dest "$REMOTE_BASIS")
fi

if [[ "$APPLY" -eq 0 ]]; then
	RSYNC_ARGS+=(--dry-run)
fi

info "Syncing payload..."
rsync "${RSYNC_ARGS[@]}" "$SOURCE/" "$HOST:$REMOTE_RELEASE/"

if [[ "$APPLY" -eq 0 ]]; then
	info "Dry-run complete. No remote files were changed."
	exit 0
fi

info "Switching live public folder..."
ssh "$HOST" "
set -e
if [ -e '$REMOTE_CURRENT' ] && [ ! -L '$REMOTE_CURRENT' ]; then
	mv '$REMOTE_CURRENT' '$REMOTE_RELEASES/initial-placeholder-$RELEASE'
fi
ln -sfn '$REMOTE_RELEASE' '$REMOTE_ROOT/public.next'
mv -Tf '$REMOTE_ROOT/public.next' '$REMOTE_CURRENT'
"

info "Pruning old releases..."
ssh "$HOST" "find '$REMOTE_RELEASES' -mindepth 1 -maxdepth 1 -type d | sort -r | tail -n +$((KEEP + 1)) | xargs -r rm -rf"

info "Verifying live endpoint..."
curl -fsS "https://wonderkitchen.tnisoft.ro/manifest.json" >/dev/null
curl -fsS "https://wonderkitchen.tnisoft.ro/catalogs/ro/manifest.json" >/dev/null

info "WonderKitchen deployed: $RELEASE"
