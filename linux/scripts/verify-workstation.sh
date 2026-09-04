#!/usr/bin/env bash

set -uo pipefail

usage() {
    cat <<'EOF'
Run the read-only MasterChief workstation verification report.

Usage:
  verify-workstation.sh [--remote]

When run outside MasterChief, the script connects to MasterChief over SSH and
uses remote mode automatically. Remote mode skips graphical-session checks that
cannot be measured accurately over SSH.
EOF
}

remote_mode=0
case "${1:-}" in
    "") ;;
    --remote) remote_mode=1 ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

station_name="$(hostname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')"
if [[ "$station_name" != "masterchief" && "$remote_mode" -eq 0 ]]; then
    command -v ssh > /dev/null 2>&1 || {
        echo "Error: ssh is required to verify MasterChief remotely." >&2
        exit 1
    }
    remote_host="${FORGE_MASTERCHIEF_SSH_HOST:-oliver@masterchief}"
    exec ssh "$remote_host" \
        "\$HOME/mac-forge/linux/scripts/verify-workstation.sh --remote"
fi

if [[ "$station_name" != "masterchief" ]]; then
    echo "Error: --remote must execute on MasterChief." >&2
    exit 1
fi

failures=0
warnings=0
skipped=0
FORGE_ROOT="${FORGE_ROOT:-$HOME/mac-forge}"

if [[ "$remote_mode" -eq 1 ]]; then
    export PATH="$HOME/.local/bin:$PATH:$HOME/.local/share/JetBrains/Toolbox/scripts"
    export NVM_DIR="$HOME/.nvm"
    if [[ -s "$NVM_DIR/nvm.sh" ]]; then
        # shellcheck source=/dev/null
        source "$NVM_DIR/nvm.sh"
        nvm use --silent default > /dev/null 2>&1 || true
    fi
fi

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

skip() {
    printf 'SKIP  %s\n' "$1"
    skipped=$((skipped + 1))
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

    if pacman -Q "$package_name" > /dev/null 2>&1; then
        pass "package installed: ${package_name}"
    else
        fail "package missing: ${package_name}"
    fi
}

check_optional_package() {
    local package_name="$1"

    if pacman -Q "$package_name" > /dev/null 2>&1; then
        pass "optional package installed: ${package_name}"
    else
        warn "optional package missing: ${package_name}"
    fi
}

check_optional_command() {
    local command_name="$1"

    if command -v "$command_name" > /dev/null 2>&1; then
        pass "optional command available: ${command_name}"
    else
        warn "optional command missing: ${command_name}"
    fi
}

check_optional_service() {
    local unit_name="$1"
    local state

    if ! systemctl cat "$unit_name" > /dev/null 2>&1; then
        skip "optional service is not installed: ${unit_name}"
        return
    fi

    state="$(systemctl is-active "$unit_name" 2>/dev/null || true)"
    if [[ "$state" == "active" ]]; then
        pass "optional service active: ${unit_name}"
    else
        warn "optional service inactive: ${unit_name}"
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

check_zsh_alias() {
    local alias_name="$1"
    local expected_value="$2"
    local alias_file="${FORGE_ROOT}/linux/aliases.zsh"

    if FORGE_ALIAS_FILE="$alias_file" \
        FORGE_ALIAS_NAME="$alias_name" \
        FORGE_ALIAS_EXPECTED="$expected_value" \
        zsh -dfc 'source "$FORGE_ALIAS_FILE"; [[ "${aliases[$FORGE_ALIAS_NAME]-}" == "$FORGE_ALIAS_EXPECTED" ]]' \
        > /dev/null 2>&1; then
        pass "Linux alias configured: ${alias_name}"
    else
        fail "Linux alias missing or incorrect: ${alias_name}"
    fi
}

check_agent_identity() {
    local identity="$1"
    local display_name="$2"
    local universe_root="$3"
    local station_inventory="${FORGE_ROOT}/configs/stations.json"
    local owner
    local pane_path
    local variable
    local expected
    local actual

    if [[ -d "$universe_root" ]]; then
        pass "${display_name} universe exists: ${universe_root}"
    else
        fail "${display_name} universe missing: ${universe_root}"
        return
    fi

    owner="$(stat -c '%U' "$universe_root" 2>/dev/null || true)"
    if [[ "$owner" == "oliver" ]]; then
        pass "${display_name} universe owner: oliver"
    else
        fail "${display_name} universe owner is ${owner:-unknown}; expected oliver"
    fi

    if [[ -w "$universe_root" ]]; then
        pass "${display_name} universe is writable by the current user"
    else
        fail "${display_name} universe is not writable by the current user"
    fi

    if command -v jq > /dev/null 2>&1 \
        && jq -e \
            --arg identity "$identity" \
            --arg universe_root "$universe_root" \
            '.stations[]
                | select(.id == "masterchief")
                | .agentRuntime.identities[]
                | select(
                    .id == $identity
                    and .universeRoot == $universe_root
                    and .workRoot == $universe_root
                    and .tmuxSocket == $identity
                    and .tmuxSession == $identity
                    and .attachCommand == $identity
                )' \
            "$station_inventory" > /dev/null 2>&1; then
        pass "${display_name} inventory configuration"
    else
        fail "${display_name} inventory configuration is missing or inconsistent"
    fi

    if ! tmux -L "$identity" has-session -t "$identity" 2>/dev/null; then
        pass "${display_name} session is stopped (valid state)"
        return
    fi

    pass "${display_name} session is running"
    for variable in FORGE_AGENT_IDENTITY FORGE_UNIVERSE_ROOT FORGE_WORK_ROOT; do
        case "$variable" in
            FORGE_AGENT_IDENTITY) expected="$identity" ;;
            *) expected="$universe_root" ;;
        esac
        actual="$(tmux -L "$identity" show-environment -t "$identity" "$variable" 2>/dev/null || true)"
        if [[ "$actual" == "${variable}=${expected}" ]]; then
            pass "${display_name} session environment: ${variable}"
        else
            fail "${display_name} session environment: ${variable}"
        fi
    done

    pane_path="$(tmux -L "$identity" display-message -p -t "$identity:0.0" '#{pane_current_path}' 2>/dev/null || true)"
    case "$pane_path" in
        "$universe_root" | "$universe_root"/*)
            pass "${display_name} pane remains inside its universe"
            ;;
        *)
            fail "${display_name} pane is outside its universe: ${pane_path:-unknown}"
            ;;
    esac
}

echo "Omarchy workstation verification"
echo

if [[ "$remote_mode" -eq 1 ]]; then
    skip "Hyprland Wayland session is not observable accurately over SSH"
elif [[ "${XDG_CURRENT_DESKTOP:-}" == *Hyprland* \
    && "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
    pass "Omarchy Hyprland Wayland session"
else
    fail "expected Omarchy Hyprland Wayland; found ${XDG_CURRENT_DESKTOP:-unknown}/${XDG_SESSION_TYPE:-unknown}"
fi

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
fi
if [[ "${ID:-}" == "omarchy" ]]; then
    pass "Omarchy distribution"
else
    fail "expected Omarchy distribution; found ${ID:-unknown}"
fi

if findmnt -rn --target /data -o OPTIONS 2>/dev/null | tr ',' '\n' | grep -qx rw; then
    pass "/data is mounted read/write"
else
    warn "/data is not mounted read/write; local Docker storage is expected"
fi

for package_name in \
    acl \
    base-devel \
    bubblewrap \
    docker \
    docker-compose \
    dotnet-sdk-8.0 \
    dotnet-sdk-9.0 \
    dotnet-sdk-10.0 \
    ghostty \
    glib2 \
    mise \
    openssh \
    python \
    rsync \
    xdg-desktop-portal-hyprland \
    fzf \
    jq \
    tmux; do
    check_package "$package_name"
done

for package_name in \
    cifs-utils \
    openconnect \
    samba \
    ydotool \
    zsh; do
    check_optional_package "$package_name"
done

for command_name in \
    git jq dotnet node npm yarn ng code docker ssh tmux bwrap fzf \
    codex claude copilot; do
    check_command "$command_name"
done

for command_name in rider sqlcmd; do
    check_optional_command "$command_name"
done

echo
echo "MasterChief agent verification"
echo

if [[ -x "${FORGE_ROOT}/scripts/masterchief-agent-session.sh" ]]; then
    pass "agent session manager is executable"
else
    fail "agent session manager is missing or not executable"
fi

if [[ -r "${FORGE_ROOT}/linux/dotfiles/agent-universe.zsh" ]]; then
    pass "agent universe shell guard is readable"
else
    fail "agent universe shell guard is missing or unreadable"
fi

if command -v jq > /dev/null 2>&1 \
    && jq -e \
        '.stations[]
            | select(.id == "masterchief")
            | .agentRuntime.maxConcurrentAgents == 2
                and .agentRuntime.directoryOwner == "oliver"' \
        "${FORGE_ROOT}/configs/stations.json" > /dev/null 2>&1; then
    pass "MasterChief agent runtime inventory"
else
    fail "MasterChief agent runtime inventory is missing or inconsistent"
fi

check_zsh_alias verify-workstation '~/mac-forge/linux/scripts/verify-workstation.sh'
check_zsh_alias vw verify-workstation
check_zsh_alias raynor '~/mac-forge/scripts/masterchief-agent-session.sh raynor'
check_zsh_alias zeratul '~/mac-forge/scripts/masterchief-agent-session.sh zeratul'
check_zsh_alias h2mc '~/mac-forge/scripts/git-peer-fetch.sh hades work'
check_zsh_alias h2r '~/mac-forge/scripts/git-peer-fetch.sh hades raynor'
check_zsh_alias h2z '~/mac-forge/scripts/git-peer-fetch.sh hades zeratul'

check_agent_identity raynor Raynor /home/oliver/raynor
check_agent_identity zeratul Zeratul /home/oliver/zeratul

check_active_service NetworkManager.service
check_optional_service bluetooth.service
check_optional_service avahi-daemon.service

if findmnt -rn --target /data > /dev/null 2>&1; then
    check_optional_service smb.service
    check_optional_service nmb.service
else
    skip "SMB services are not checked because /data is not mounted"
fi

if systemctl --user is-active --quiet ydotool.service; then
    pass "user service active: ydotool.service"
else
    warn "user service inactive: ydotool.service"
fi

if pacman -Q xdg-desktop-portal-hyprland > /dev/null 2>&1; then
    pass "Hyprland desktop portal is installed"
else
    warn "Hyprland desktop portal is not installed"
fi

if systemctl is-enabled --quiet docker.service 2>/dev/null; then
    warn "Docker is enabled at boot; this workstation expects on-demand startup"
else
    pass "Docker remains disabled at boot"
fi

if [[ -r /etc/docker/daemon.json ]] \
    && command -v jq > /dev/null 2>&1 \
    && docker_root="$(jq -r '."data-root" // "/var/lib/docker"' /etc/docker/daemon.json 2>/dev/null)" \
    && [[ -n "$docker_root" && "$docker_root" != "null" ]]; then
    if [[ "$docker_root" == "/var/lib/docker" ]]; then
        pass "Docker uses the system storage path"
    else
        pass "Docker data root configured: ${docker_root}"
    fi
else
    warn "Docker daemon configuration is not readable; the default storage path may be in use"
fi

if [[ "$remote_mode" -eq 1 ]]; then
    skip "desktop SSH-agent state is not observable accurately over SSH"
elif ssh-add -l > /dev/null 2>&1; then
    pass "SSH agent has loaded identities"
else
    warn "SSH agent has no loaded identities"
fi

if [[ "$remote_mode" -eq 1 ]]; then
    skip "connected displays are not observable accurately over SSH"
elif command -v hyprctl > /dev/null 2>&1 && command -v jq > /dev/null 2>&1; then
    connected_outputs="$(hyprctl monitors -j 2>/dev/null | jq 'length' 2>/dev/null || printf '0')"
    if (( connected_outputs >= 2 )); then
        pass "internal and external displays are connected"
    elif (( connected_outputs == 1 )); then
        warn "only one display is currently connected"
    else
        fail "Hyprland reports no connected display"
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
printf 'Result: %d failure(s), %d warning(s), %d skipped\n' \
    "$failures" "$warnings" "$skipped"

(( failures == 0 ))
