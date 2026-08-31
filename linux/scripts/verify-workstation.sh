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

echo "Plasma workstation verification"
echo

if [[ "$remote_mode" -eq 1 ]]; then
    skip "Plasma Wayland session is not observable accurately over SSH"
elif [[ "${XDG_CURRENT_DESKTOP:-}" == *KDE* \
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
    bubblewrap \
    dolphin \
    fzf \
    plasma-discover \
    tmux; do
    check_package "$package_name"
done

for command_name in \
    git jq dotnet node npm yarn ng code rider docker sqlcmd openconnect ssh tmux bwrap fzf zsh \
    codex claude copilot; do
    check_command "$command_name"
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

if command -v jq > /dev/null 2>&1 \
    && [[ -r /etc/docker/daemon.json ]] \
    && jq -e '."data-root" == "/data/docker/engine"' /etc/docker/daemon.json \
        > /dev/null 2>&1; then
    pass "Docker data root configured under /data"
else
    fail "Docker data root is not configured as /data/docker/engine"
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
elif command -v kscreen-doctor > /dev/null 2>&1; then
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
printf 'Result: %d failure(s), %d warning(s), %d skipped\n' \
    "$failures" "$warnings" "$skipped"

(( failures == 0 ))
