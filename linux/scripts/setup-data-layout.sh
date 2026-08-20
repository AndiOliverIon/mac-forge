#!/usr/bin/env bash

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Run this script as root." >&2
    exit 1
fi

DATA_USER="${SUDO_USER:-oliver}"
DATA_GROUP="$(id -gn "${DATA_USER}")"
SQL_UID="10001"

create_owned_dir() {
    local mode="$1"
    local path="$2"

    if [[ ! -d "${path}" ]]; then
        install -d -o "${DATA_USER}" -g "${DATA_GROUP}" -m "${mode}" "${path}"
    fi
}

findmnt -rn /data > /dev/null || {
    echo "ERROR: /data is not mounted. Configure the Data SSD in /etc/fstab first." >&2
    exit 1
}

findmnt -no OPTIONS /data | grep -qw rw || {
    echo "ERROR: /data is not mounted read/write." >&2
    exit 1
}

for path in \
    /data/sql \
    /data/sql/snapshot \
    /data/sql/snapshots \
    /data/sql/docker \
    /data/sql/docker/data \
    /data/sql/docker/snapshots; do
    create_owned_dir 0755 "${path}"
done

install -d -o root -g root -m 0755 /data/docker

for path in /data/sql/docker/data /data/sql/docker/snapshots; do
    setfacl -m "u:${DATA_USER}:rwx,u:${SQL_UID}:rwx" "${path}"
    setfacl -d -m "u:${DATA_USER}:rwx,u:${SQL_UID}:rwx" "${path}"
done

echo "Data layout prepared under /data."
