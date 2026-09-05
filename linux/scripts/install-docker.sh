#!/usr/bin/env bash

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Run this script as root." >&2
    exit 1
fi

command -v omarchy > /dev/null 2>&1 || {
    echo "ERROR: omarchy is required; this installer targets Omarchy/Arch Linux." >&2
    exit 1
}

INSTALL_USER="${SUDO_USER:-oliver}"
DATA_ROOT="${FORGE_DOCKER_DATA_ROOT:-}"
DOCKER_CONFIG="/etc/docker/daemon.json"
CONTAINERD_CONFIG="/etc/containerd/config.toml"

if [[ -z "${DATA_ROOT}" ]]; then
    if findmnt -rn --target /data > /dev/null 2>&1 \
        && findmnt -no OPTIONS /data | tr ',' '\n' | grep -qx rw; then
        DATA_ROOT="/data/docker/engine"
    else
        DATA_ROOT="/var/lib/docker"
    fi
fi

omarchy pkg add docker docker-compose containerd

systemctl stop docker.service docker.socket containerd.service 2>/dev/null || true

install -d -m 0755 /etc/docker /etc/containerd
if [[ -e "${DOCKER_CONFIG}" && ! -e "${DOCKER_CONFIG}.before-forge" ]]; then
    cp -a "${DOCKER_CONFIG}" "${DOCKER_CONFIG}.before-forge"
fi

if [[ "${DATA_ROOT}" == "/var/lib/docker" ]]; then
    cat > "${DOCKER_CONFIG}" <<'EOF'
{
  "log-driver": "local",
  "log-opts": {
    "max-size": "20m",
    "max-file": "5"
  }
}
EOF
else
    install -d -m 0711 "${DATA_ROOT}"
    cat > "${DOCKER_CONFIG}" <<EOF
{
  "data-root": "${DATA_ROOT}",
  "log-driver": "local",
  "log-opts": {
    "max-size": "20m",
    "max-file": "5"
  }
}
EOF
fi

containerd config default > "${CONTAINERD_CONFIG}"
if [[ "${DATA_ROOT}" != "/var/lib/docker" ]]; then
    install -d -m 0711 "$(dirname -- "${DATA_ROOT}")/containerd"
    sed -i "s|^root = .*|root = \"$(dirname -- "${DATA_ROOT}")/containerd\"|" "${CONTAINERD_CONFIG}"
fi

dockerd --validate --config-file="${DOCKER_CONFIG}"

usermod -aG docker "${INSTALL_USER}"
systemctl daemon-reload
systemctl enable --now containerd.service
systemctl disable docker.service docker.socket 2>/dev/null || true

echo
echo "Docker Engine installation completed."
echo "Docker data root: ${DATA_ROOT}"
echo "Docker remains disabled at boot; start it with 'docker-on'."
echo "Log out and back in before using Docker without sudo."
