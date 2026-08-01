#!/usr/bin/env bash

set -uo pipefail

failures=0
warnings=0

pass() {
    printf 'PASS  %s\n' "$1"
}

warn() {
    printf 'WARN  %s\n' "$1"
    warnings=$((warnings + 1))
}

fail() {
    printf 'FAIL  %s\n' "$1"
    failures=$((failures + 1))
}

check_command() {
    local command_name="$1"

    if command -v "$command_name" > /dev/null 2>&1; then
        pass "command available: ${command_name}"
    else
        fail "command missing: ${command_name}"
    fi
}

check_package() {
    local package_name="$1"

    if dpkg-query -W -f='${db:Status-Abbrev}' "$package_name" 2>/dev/null \
        | grep -qx 'ii '; then
        pass "package installed: ${package_name}"
    else
        fail "package missing: ${package_name}"
    fi
}

check_active_service() {
    local unit_name="$1"
    local state

    if ! state="$(systemctl is-active "$unit_name" 2>/dev/null)"; then
        if [[ "$state" == "inactive" || "$state" == "failed" ]]; then
            fail "service inactive: ${unit_name}"
        else
            fail "could not query service: ${unit_name}"
        fi
    elif [[ "$state" == "active" ]]; then
        pass "service active: ${unit_name}"
    else
        fail "service inactive: ${unit_name}"
    fi
}

echo "Plasma workstation verification"
echo

if [[ "${XDG_CURRENT_DESKTOP:-}" == *KDE* \
    && "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
    pass "Plasma Wayland session"
else
    fail "expected Plasma Wayland; found ${XDG_CURRENT_DESKTOP:-unknown}/${XDG_SESSION_TYPE:-unknown}"
fi

if [[ "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)" \
    == "/usr/lib/systemd/system/sddm.service" ]]; then
    pass "SDDM owns the display-manager service"
else
    fail "SDDM does not own the display-manager service"
fi

if findmnt -rn --target /data -o OPTIONS 2>/dev/null | tr ',' '\n' | grep -qx rw; then
    pass "/data is mounted read/write"
else
    fail "/data is not mounted read/write"
fi

for package_name in \
    kde-plasma-desktop \
    plasma-workspace \
    sddm \
    sddm-theme-breeze \
    xdg-desktop-portal-kde \
    dolphin \
    plasma-discover; do
    check_package "$package_name"
done

for command_name in \
    git dotnet node npm yarn ng code rider docker sqlcmd openconnect ssh \
    codex claude copilot; do
    check_command "$command_name"
done

check_active_service NetworkManager.service
check_active_service bluetooth.service
check_active_service smbd.service
check_active_service avahi-daemon.service

if systemctl --user is-active --quiet ydotool.service; then
    pass "user service active: ydotool.service"
else
    fail "user service inactive: ydotool.service"
fi

if systemctl --user is-active --quiet plasma-xdg-desktop-portal-kde.service; then
    pass "KDE desktop portal is active"
else
    fail "KDE desktop portal is inactive"
fi

if systemctl is-enabled --quiet docker.service 2>/dev/null; then
    warn "Docker is enabled at boot; this workstation expects on-demand startup"
else
    pass "Docker remains disabled at boot"
fi

if [[ -r /etc/docker/daemon.json ]] \
    && jq -e '."data-root" == "/data/docker/engine"' /etc/docker/daemon.json \
        > /dev/null 2>&1; then
    pass "Docker data root configured under /data"
else
    fail "Docker data root is not configured as /data/docker/engine"
fi

if ssh-add -l > /dev/null 2>&1; then
    pass "SSH agent has loaded identities"
else
    warn "SSH agent has no loaded identities"
fi

if command -v kscreen-doctor > /dev/null 2>&1; then
    connected_outputs="$(kscreen-doctor -o 2>/dev/null | grep -c 'connected')"
    if (( connected_outputs >= 2 )); then
        pass "internal and external displays are connected"
    elif (( connected_outputs == 1 )); then
        warn "only one display is currently connected"
    else
        fail "KScreen reports no connected display"
    fi
fi

if ! failed_system_units="$(systemctl --failed --no-legend 2>/dev/null)"; then
    fail "could not query failed system units"
elif [[ -n "$failed_system_units" ]]; then
    fail "systemd reports failed system units"
else
    pass "no failed system units"
fi

if ! failed_user_units="$(systemctl --user --failed --no-legend 2>/dev/null)"; then
    fail "could not query failed user units"
elif [[ -n "$failed_user_units" ]]; then
    fail "systemd reports failed user units"
else
    pass "no failed user units"
fi

echo
printf 'Result: %d failure(s), %d warning(s)\n' "$failures" "$warnings"

(( failures == 0 ))
