#!/opt/homebrew/bin/bash
# vps1-bl-publish.sh — build and publish the BookingLounge API to a vps1 endpoint.
#
# Two targets, chosen interactively (or as the first argument):
#   development -> bookinglounge-api@dev  (port 5081, DB bookinglounge-dev)
#                  Standard flow, no git gate. Publishes whatever you have.
#   production  -> bookinglounge-api@prod (port 5080, DB bookinglounge, PUBLIC)
#                  GATED: refuses unless the BookingLounge repo is on `main`
#                  AND the working tree is clean (no pending changes).
#
# Flow: dotnet publish (self-contained linux-x64) -> rsync into the shared
# releases/ pool on vps1 -> repoint that endpoint's build symlink + restart only
# that service (via Backend/deploy/vps1-deploy-instance.sh, run with sudo).
#
# The other endpoint is never touched. test stays gate-only (run-backend-tests.sh).
#
# Usage:
#   vps1-bl-publish.sh                 # prompt for target
#   vps1-bl-publish.sh development
#   vps1-bl-publish.sh production
#   vps1-bl-publish.sh --dry-run dev   # build + show plan, ship nothing
#   vps1-bl-publish.sh --help
set -euo pipefail

#######################################
# Static config
#######################################
BL_REPO="${BL_REPO:-$HOME/projects/bookinglounge}"
VPS1_SSH_HOST="${VPS1_SSH_HOST:-vps1}"
BL_API_ROOT="${BL_API_ROOT:-/srv/tnisoft/bookinglounge-api}"
BL_PUBLIC_HEALTH_URL="${BL_PUBLIC_HEALTH_URL:-https://api.bookinglounge.tnisoft.ro/health}"
BL_CSPROJ="$BL_REPO/Backend/BookingLounge.Api/BookingLounge.Api.csproj"
BL_DEPLOY_HELPER="$BL_REPO/Backend/deploy/vps1-deploy-instance.sh"
BL_PUBLISH_RUNTIME="${BL_PUBLISH_RUNTIME:-linux-x64}"

#######################################
# Helpers
#######################################
die() { echo "✖ $*" >&2; exit 1; }
log() { echo "→ $*"; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."; }

usage() { sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

#######################################
# Parse args
#######################################
DRY_RUN=0
TARGET=""
while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --help|-h) usage; exit 0 ;;
    production|prod) TARGET="production"; shift ;;
    development|dev) TARGET="development"; shift ;;
    *) die "Unknown argument: $1 (expected production|development|--dry-run|--help)" ;;
  esac
done

#######################################
# Preconditions
#######################################
require_cmd dotnet
require_cmd git
require_cmd ssh
require_cmd rsync
require_cmd curl
require_cmd fzf

[[ -d "$BL_REPO/.git" ]] || die "BookingLounge repo not found at: $BL_REPO (set BL_REPO=...)"
[[ -f "$BL_CSPROJ" ]] || die "API project not found: $BL_CSPROJ"
[[ -f "$BL_DEPLOY_HELPER" ]] || die "Deploy helper not found: $BL_DEPLOY_HELPER"

#######################################
# Choose target
#######################################
if [[ -z "$TARGET" ]]; then
  TARGET="$(printf 'development\nproduction\n' \
    | fzf --prompt='BookingLounge publish target > ' --height=20% --layout=reverse --border)" \
    || die "No target selected."
fi

case "$TARGET" in
  production)  ENV_KEY="prod"; PORT=5080 ;;
  development) ENV_KEY="dev";  PORT=5081 ;;
  *) die "Invalid target: $TARGET" ;;
esac

#######################################
# Git state (from the BookingLounge repo)
#######################################
branch="$(git -C "$BL_REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
short_sha="$(git -C "$BL_REPO" rev-parse --short HEAD 2>/dev/null || echo 'nosha')"
dirty=0
[[ -n "$(git -C "$BL_REPO" status --porcelain 2>/dev/null)" ]] && dirty=1

#######################################
# Production safety gate
#######################################
if [[ "$TARGET" == "production" ]]; then
  log "Production gate: verifying repo state..."
  [[ "$branch" == "main" ]] \
    || die "Production publish requires branch 'main' (current: '$branch'). Aborted."
  (( dirty == 0 )) \
    || die "Production publish requires a clean working tree (you have pending changes). Aborted."
  log "Gate passed: on 'main', no pending changes (HEAD $short_sha)."
fi

#######################################
# Verify the endpoint exists on vps1 (migration ran)
#######################################
log "Checking vps1 endpoint readiness..."
ssh "$VPS1_SSH_HOST" "test -f /etc/systemd/system/bookinglounge-api@.service" \
  || die "Template unit bookinglounge-api@.service missing on $VPS1_SSH_HOST. Run Backend/deploy/vps1-migrate-to-multi-instance.sh first."
ssh "$VPS1_SSH_HOST" "test -e '$BL_API_ROOT/current-$ENV_KEY'" \
  || die "Build pointer current-$ENV_KEY missing on $VPS1_SSH_HOST. Run the migration first."

#######################################
# Release name + summary
#######################################
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
label="${branch//\//-}_${short_sha}"
(( dirty == 1 )) && label="${label}-dirty"
release="${stamp}_${ENV_KEY}_${label}"
remote_release="$BL_API_ROOT/releases/$release"

echo
echo "──────────────────────────────────────────────"
echo "  BookingLounge publish"
echo "  Target     : $TARGET  (bookinglounge-api@$ENV_KEY, port $PORT)"
echo "  Repo       : $BL_REPO"
echo "  Branch/SHA : $branch @ $short_sha$([[ $dirty == 1 ]] && echo '  (dirty)')"
echo "  Release    : $release"
echo "  vps1 path  : $VPS1_SSH_HOST:$remote_release"
(( DRY_RUN == 1 )) && echo "  Mode       : DRY-RUN (build only, nothing shipped)"
echo "──────────────────────────────────────────────"
echo

#######################################
# Confirm production
#######################################
if [[ "$TARGET" == "production" && "$DRY_RUN" -eq 0 ]]; then
  echo "⚠ This publishes to the PUBLIC production endpoint."
  echo "  Type 'production' to confirm."
  read -r -p "> " answer
  [[ "$answer" == "production" ]] || die "Confirmation mismatch. Aborted (nothing published)."
fi

#######################################
# Build (dotnet publish, self-contained)
#######################################
pub_dir="$(mktemp -d -t bl-publish-XXXXXX)"
cleanup() { rm -rf "$pub_dir"; }
trap cleanup EXIT

log "Building (Release, $BL_PUBLISH_RUNTIME, self-contained, single file)..."
dotnet publish "$BL_CSPROJ" \
  -c Release \
  -r "$BL_PUBLISH_RUNTIME" \
  --self-contained true \
  /p:PublishSingleFile=true \
  -o "$pub_dir"

[[ -x "$pub_dir/BookingLounge.Api" ]] || die "Build did not produce an executable BookingLounge.Api."

if (( DRY_RUN == 1 )); then
  log "DRY-RUN: build complete at $pub_dir. Skipping rsync + deploy."
  echo "Would ship to: $VPS1_SSH_HOST:$remote_release  and repoint current-$ENV_KEY."
  exit 0
fi

#######################################
# Ship: rsync into releases/ pool
#######################################
log "Uploading release to $VPS1_SSH_HOST:$remote_release ..."
ssh "$VPS1_SSH_HOST" "mkdir -p '$remote_release'"
rsync -az --delete --exclude '.DS_Store' --exclude '._*' \
  "$pub_dir/" "$VPS1_SSH_HOST:$remote_release/"

#######################################
# Repoint endpoint symlink + restart that service only (needs sudo on vps1)
#######################################
log "Activating release on the $TARGET endpoint (sudo on $VPS1_SSH_HOST)..."
scp -q "$BL_DEPLOY_HELPER" "$VPS1_SSH_HOST:/tmp/vps1-deploy-instance.sh"
ssh -t "$VPS1_SSH_HOST" "sudo bash /tmp/vps1-deploy-instance.sh '$ENV_KEY' 'releases/$release'"

#######################################
# Verify
#######################################
if [[ "$TARGET" == "production" ]]; then
  log "Verifying public endpoint..."
  curl -fsS "$BL_PUBLIC_HEALTH_URL" >/dev/null && echo "  public health OK: $BL_PUBLIC_HEALTH_URL"
fi

echo
echo "✔ Published $release to $TARGET (bookinglounge-api@$ENV_KEY)."
[[ "$TARGET" == "development" ]] && \
  echo "  Reach it: ssh -L 5081:127.0.0.1:5081 $VPS1_SSH_HOST  ->  http://localhost:5081"
