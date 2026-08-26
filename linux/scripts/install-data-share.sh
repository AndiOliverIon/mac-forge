#!/usr/bin/env bash

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Run this script as root." >&2
    exit 1
fi

SHARE_USER="${SUDO_USER:-oliver}"
SHARE_PATH="/data"
LAN_INTERFACE="${LAN_INTERFACE:-$(ip route show default | awk 'NR == 1 { print $5 }')}"
LAN_SUBNET="${LAN_SUBNET:-$(ip -o -4 route show dev "${LAN_INTERFACE}" proto kernel scope link | awk 'NR == 1 { print $1 }')}"
SMB_CONFIG="/etc/samba/smb.conf"
STATION_NAME="masterchief"

[[ -n "${LAN_INTERFACE}" && -n "${LAN_SUBNET}" ]] || {
    echo "ERROR: Could not derive the LAN subnet; set LAN_INTERFACE or LAN_SUBNET explicitly." >&2
    exit 1
}

findmnt -rn "${SHARE_PATH}" > /dev/null || {
    echo "ERROR: ${SHARE_PATH} is not mounted." >&2
    exit 1
}

findmnt -no OPTIONS "${SHARE_PATH}" | grep -qw rw || {
    echo "ERROR: ${SHARE_PATH} is not mounted read/write." >&2
    exit 1
}

getent passwd "${SHARE_USER}" > /dev/null || {
    echo "ERROR: Linux user does not exist: ${SHARE_USER}" >&2
    exit 1
}

apt-get update
apt-get install -y samba smbclient

if [[ ! -f "${SMB_CONFIG}.before-data-share" ]]; then
    cp -a "${SMB_CONFIG}" "${SMB_CONFIG}.before-data-share"
fi

if ! grep -q '^[[:space:]]*netbios name[[:space:]]*=' "${SMB_CONFIG}"; then
    sed -i "/^\\[global\\]$/a\\   netbios name = ${STATION_NAME^^}" "${SMB_CONFIG}"
fi

if ! grep -q '^\[Data\]$' "${SMB_CONFIG}"; then
    cat >> "${SMB_CONFIG}" <<EOF

[Data]
   comment = Permanent Data SSD
   path = ${SHARE_PATH}
   browseable = yes
   read only = no
   guest ok = no
   valid users = ${SHARE_USER}
   force user = ${SHARE_USER}
   force group = ${SHARE_USER}
   create mask = 0664
   directory mask = 0775
   hosts allow = ${LAN_SUBNET} 127.0.0.1
   hosts deny = 0.0.0.0/0
EOF
fi

testparm -s "${SMB_CONFIG}" > /dev/null

if command -v ufw > /dev/null 2>&1; then
    ufw allow from "${LAN_SUBNET}" to any app Samba
fi

systemctl enable --now smbd.service nmbd.service
systemctl restart smbd.service nmbd.service

echo
echo "Data share configured."
echo "Set the SMB password with: sudo smbpasswd -a ${SHARE_USER}"
echo "Connect from macOS to: smb://${STATION_NAME}/Data"
echo "macOS fallback: smb://${STATION_NAME}.local/Data"
