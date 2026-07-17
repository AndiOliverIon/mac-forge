#!/usr/bin/env bash

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Run this script as root." >&2
    exit 1
fi

INSTALL_USER="${SUDO_USER:-oliver}"
DATA_ROOT="/data/docker"

findmnt -rn /data > /dev/null || {
    echo "ERROR: /data is not mounted." >&2
    exit 1
}

findmnt -no OPTIONS /data | grep -qw rw || {
    echo "ERROR: /data is not mounted read/write." >&2
    exit 1
}

apt-get update
apt-get install -y ca-certificates curl

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

. /etc/os-release
cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt-get update
apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

systemctl stop docker.service docker.socket containerd.service

install -d -m 0711 "${DATA_ROOT}/engine"
install -d -m 0711 "${DATA_ROOT}/containerd"
install -d -m 0755 /etc/docker /etc/containerd

cat > /etc/docker/daemon.json <<EOF
{
  "data-root": "${DATA_ROOT}/engine",
  "log-driver": "local",
  "log-opts": {
    "max-size": "20m",
    "max-file": "5"
  }
}
EOF

containerd config default > /etc/containerd/config.toml
sed -i \
    "s|^root = .*|root = \"${DATA_ROOT}/containerd\"|" \
    /etc/containerd/config.toml

dockerd --validate --config-file=/etc/docker/daemon.json

usermod -aG docker "${INSTALL_USER}"
systemctl daemon-reload
systemctl enable --now containerd.service docker.service

docker run --rm hello-world

echo
echo "Docker Engine installation completed."
echo "Docker data root: ${DATA_ROOT}"
echo "Log out and back in before using Docker without sudo."
