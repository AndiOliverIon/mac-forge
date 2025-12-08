#!/opt/homebrew/bin/bash
set -euo pipefail

#######################################
# Load forge config (if present)
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/forge.sh" ]]; then
	# shellcheck disable=SC1091
	source "$SCRIPT_DIR/forge.sh"
elif [[ -f "$HOME/mac-forge/forge.sh" ]]; then
	# shellcheck disable=SC1091
	source "$HOME/mac-forge/forge.sh"
fi

#######################################
# Helpers
#######################################
die() {
	echo "✖ $*" >&2
	exit 1
}

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."
}

#######################################
# Ensure Docker daemon is running
# - If not, start Docker Desktop and wait
#######################################
ensure_docker_running() {
	require_cmd docker

	# Fast path: Docker is already running
	if docker info >/dev/null 2>&1; then
		return 0
	fi

	echo "Docker daemon not reachable. Starting Docker Desktop..."

	# Try to start Docker Desktop (macOS)
	if command -v open >/dev/null 2>&1; then
		open -g -a Docker || open -a Docker || true
	fi

	echo "Waiting for Docker to become ready..."

	local max_tries=60
	local i
	for ((i = 1; i <= max_tries; i++)); do
		if docker info >/dev/null 2>&1; then
			echo "Docker is ready (attempt $i)."
			return 0
		fi

		echo "  ... not ready yet (attempt $i), retrying in 2s"
		sleep 2
	done

	die "Docker daemon did not become ready in time."
}

#######################################
# Preconditions
#######################################
ensure_docker_running

#######################################
# Collect stopped containers
#######################################
STOPPED_CONTAINERS=()

while IFS=$'\t' read -r name status; do
	[[ -z "$name" ]] && continue

	# Examples:
	#   Up 5 minutes
	#   Exited (0) 2 hours ago
	# We only include those that are NOT "Up".
	if [[ "$status" != Up* ]]; then
		STOPPED_CONTAINERS+=("$name")
	fi
done < <(docker ps -a --format '{{.Names}}\t{{.Status}}')

if ((${#STOPPED_CONTAINERS[@]} == 0)); then
	echo "No stopped containers found. Nothing to start."
	exit 0
fi

#######################################
# If exactly one container → start immediately
#######################################
if ((${#STOPPED_CONTAINERS[@]} == 1)); then
	name="${STOPPED_CONTAINERS[0]}"
	echo "Found a single stopped container: $name"
	echo "Starting '$name'..."
	docker start "$name" >/dev/null
	echo "✅ Container '$name' started."
	exit 0
fi

#######################################
# Multiple containers → ask user
#######################################
echo "Found stopped containers:"
for i in "${!STOPPED_CONTAINERS[@]}"; do
	printf "  %d) %s\n" "$((i + 1))" "${STOPPED_CONTAINERS[$i]}"
done

all_index=$((${#STOPPED_CONTAINERS[@]} + 1))
printf "  %d) All\n" "$all_index"
echo

read -r -p "Select container to start [${all_index}=All]: " choice

# Default = All if empty
if [[ -z "$choice" ]]; then
	choice="$all_index"
fi

# Validate numeric
if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
	die "Invalid choice: $choice"
fi

if ((choice < 1 || choice > all_index)); then
	die "Choice out of range: $choice"
fi

#######################################
# Start containers based on choice
#######################################
if ((choice == all_index)); then
	echo "Starting ALL stopped containers..."
	for name in "${STOPPED_CONTAINERS[@]}"; do
		echo "  → $name"
		docker start "$name" >/dev/null
	done
	echo "✅ All stopped containers started."
else
	index=$((choice - 1))
	name="${STOPPED_CONTAINERS[$index]}"
	echo "Starting container '$name'..."
	docker start "$name" >/dev/null
	echo "✅ Container '$name' started."
fi
