#!/usr/bin/env bash

set -euo pipefail

ANGULAR_CLI_VERSION="20.3.16"
FORGE_ROOT="${FORGE_ROOT:-$HOME/mac-forge}"
FORGE_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}/forge"
TOOLBOX_INSTALL_ROOT="${HOME}/.local/opt"
export PATH="${HOME}/.local/share/mise/shims:${HOME}/.local/bin:${PATH}"

step() {
    echo
    echo "[$1] $2"
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

notice() {
    echo "NOTICE: $*"
}

require_command() {
    command -v "$1" > /dev/null 2>&1 || die "Required command not found: $1"
}

install_telerik_license() {
    local destination_dir="${HOME}/.telerik"
    local destination_file="${destination_dir}/telerik-license.txt"
    local source_dir=""
    local candidate
    local -a candidates=()

    if [[ -n "${TELERIK_LICENSE_SOURCE_DIR:-}" ]]; then
        candidates+=("${TELERIK_LICENSE_SOURCE_DIR}")
    fi
    candidates+=(
        "${PWD}/.telerik"
        "${FORGE_ROOT}/.telerik"
        "/data/forge-temp/.telerik"
    )

    for candidate in "${candidates[@]}"; do
        if [[ -f "${candidate}/telerik-license.txt" ]]; then
            source_dir="${candidate}"
            break
        fi
    done

    if [[ "${source_dir}" == "${destination_dir}" ]]; then
        chmod 700 "${destination_dir}"
        chmod 600 "${destination_file}"
        echo "Telerik license already installed at ${destination_file}."
    elif [[ -n "${source_dir}" ]]; then
        install -d -m 700 "${destination_dir}"
        install -m 600 "${source_dir}/telerik-license.txt" "${destination_file}"
        echo "Telerik license installed from ${source_dir}."
        echo "The source copy was left in place; remove it after verifying the workstation."
    elif [[ -f "${destination_file}" ]]; then
        chmod 700 "${destination_dir}"
        chmod 600 "${destination_file}"
        echo "Telerik license already installed at ${destination_file}."
    else
        notice "Telerik license was not found. Place .telerik/telerik-license.txt in the launch directory or /data/forge-temp, then rerun the bootstrap."
    fi
}

install_sqlcmd() {
    if command -v sqlcmd > /dev/null 2>&1; then
        echo "sqlcmd is already installed."
        return
    fi

    if command -v yay > /dev/null 2>&1; then
        if omarchy pkg aur add mssql-tools18; then
            echo "sqlcmd installed from the mssql-tools18 AUR package."
            return
        fi
    fi

    notice "sqlcmd was not installed. The mssql-tools18 AUR package was unavailable; install it later with 'omarchy pkg aur add mssql-tools18'."
}

install_jetbrains_toolbox() {
    local toolbox_release
    local toolbox_version
    local toolbox_url
    local toolbox_checksum
    local toolbox_dir
    local toolbox_archive
    local toolbox_checksum_file
    local toolbox_stage

    toolbox_release="$(curl -fsSL 'https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release')"
    toolbox_version="$(jq -r '.TBA[0].version' <<< "${toolbox_release}")"
    toolbox_url="$(jq -r '.TBA[0].downloads.linux.link' <<< "${toolbox_release}")"
    toolbox_checksum="$(jq -r '.TBA[0].downloads.linux.checksumLink' <<< "${toolbox_release}")"

    [[ -n "${toolbox_version}" && "${toolbox_version}" != "null" ]] || die "Could not resolve the latest JetBrains Toolbox version."
    [[ -n "${toolbox_url}" && "${toolbox_url}" != "null" ]] || die "Could not resolve the JetBrains Toolbox download URL."
    [[ -n "${toolbox_checksum}" && "${toolbox_checksum}" != "null" ]] || die "Could not resolve the JetBrains Toolbox checksum URL."

    toolbox_dir="${TOOLBOX_INSTALL_ROOT}/jetbrains-toolbox-${toolbox_version}"
    if [[ ! -x "${toolbox_dir}/bin/jetbrains-toolbox" ]]; then
        toolbox_archive="$(mktemp --suffix=.tar.gz)"
        toolbox_checksum_file="$(mktemp --suffix=.sha256)"
        toolbox_stage="$(mktemp -d)"
        trap 'rm -f "${toolbox_archive}" "${toolbox_checksum_file}"; rm -rf "${toolbox_stage}"' RETURN

        curl -fsSL "${toolbox_url}" -o "${toolbox_archive}"
        curl -fsSL "${toolbox_checksum}" -o "${toolbox_checksum_file}"
        printf '%s  %s\n' "$(awk '{ print $1; exit }' "${toolbox_checksum_file}")" "${toolbox_archive}" \
            | sha256sum --check --status
        tar -xzf "${toolbox_archive}" -C "${toolbox_stage}"
        mkdir -p "${TOOLBOX_INSTALL_ROOT}"
        mv "$(find "${toolbox_stage}" -mindepth 1 -maxdepth 1 -type d -print -quit)" "${toolbox_dir}"
        rm -f "${toolbox_archive}" "${toolbox_checksum_file}"
        rm -rf "${toolbox_stage}"
        trap - RETURN
    fi

    ln -sfn "${toolbox_dir}/bin/jetbrains-toolbox" "${HOME}/.local/bin/jetbrains-toolbox"
    echo "JetBrains Toolbox ${toolbox_version} is installed. Open it and install Rider from there."
}

install_ai_cli_if_missing() {
    local command_name="$1"
    local installer_url="$2"

    if command -v "${command_name}" > /dev/null 2>&1; then
        echo "${command_name} is already installed."
    else
        echo "Installing ${command_name}..."
        curl -fsSL "${installer_url}" | bash
    fi
}

install_zsh_environment() {
    local powerlevel10k_dir="${HOME}/.oh-my-zsh/custom/themes/powerlevel10k"

    if [[ ! -d "${HOME}/.oh-my-zsh/.git" ]]; then
        RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
            "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
            "" --unattended
    fi

    if [[ ! -d "${powerlevel10k_dir}/.git" ]]; then
        git clone --depth=1 \
            https://github.com/romkatv/powerlevel10k.git \
            "${powerlevel10k_dir}"
    fi
}

[[ "${EUID}" -ne 0 ]] || die "Run this bootstrap as the normal workstation user, not as root."
[[ -d "${FORGE_ROOT}" ]] || die "Forge root was not found: ${FORGE_ROOT}"

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
fi

[[ "${ID:-}" == "omarchy" ]] || die "This bootstrap targets Omarchy. Detected distro: ${ID:-unknown}."
require_command omarchy
require_command mise

echo "========================================="
echo " Omarchy Forge Bootstrap"
echo "========================================="
echo "Distro: ${PRETTY_NAME:-Omarchy}"
echo "Desktop: ${XDG_CURRENT_DESKTOP:-unknown}/${XDG_SESSION_TYPE:-unknown}"

install -d -m 700 "${FORGE_CONFIG_HOME}"
install -d -m 755 "${HOME}/.local/bin"

step "1/10" "Installing Arch and Omarchy development packages..."
arch_packages=(
    acl
    bubblewrap
    ca-certificates
    cifs-utils
    curl
    dotnet-sdk-8.0
    dotnet-sdk-9.0
    dotnet-sdk-10.0
    gnupg
    htop
    lsof
    openbsd-netcat
    openconnect
    openssh
    python
    rsync
    visual-studio-code-bin
    wget
    yarn
    zip
    zsh
)

omarchy pkg add "${arch_packages[@]}"

step "2/10" "Installing sqlcmd when the Arch package is available..."
install_sqlcmd

step "3/10" "Configuring the mise-managed Node.js toolchain..."
mise use --global node
hash -r
npm install --global "@angular/cli@${ANGULAR_CLI_VERSION}"

step "4/10" "Installing the Telerik license when staged..."
install_telerik_license

step "5/10" "Installing JetBrains Toolbox..."
install_jetbrains_toolbox

step "6/10" "Installing missing AI command-line tools..."
install_ai_cli_if_missing claude https://claude.ai/install.sh
install_ai_cli_if_missing copilot https://gh.io/copilot-install

step "7/10" "Installing the Forge Zsh configuration..."
install_zsh_environment
"${FORGE_ROOT}/linux/scripts/link-dotfiles.sh"
echo "Omarchy Bash remains the default shell. Run 'exec zsh' to use the Forge Zsh profile."

step "8/10" "Preparing the work directory and Ghostty configuration..."
mkdir -p "${HOME}/work"
ghostty_config_dir="${HOME}/.config/ghostty"
ghostty_config="${ghostty_config_dir}/config"
if [[ -e "${ghostty_config}" || -L "${ghostty_config}" ]]; then
    notice "Keeping the existing Omarchy Ghostty configuration: ${ghostty_config}"
else
    mkdir -p "${ghostty_config_dir}"
    ln -s "${FORGE_ROOT}/dotfiles/ghostty.ghostty" "${ghostty_config}"
    echo "Linked ${ghostty_config} to the shared Forge Ghostty configuration."
fi
omarchy install terminal ghostty

step "9/10" "Configuring Docker for the available storage layout..."
sudo "${FORGE_ROOT}/linux/scripts/install-docker.sh"

if findmnt -rn --target /data > /dev/null 2>&1 \
    && findmnt -no OPTIONS /data | tr ',' '\n' | grep -qx rw; then
    step "10/10" "Preparing the mounted Data SSD and SMB share..."
    sudo "${FORGE_ROOT}/linux/scripts/setup-data-layout.sh"
    sudo "${FORGE_ROOT}/linux/scripts/install-data-share.sh"
else
    step "10/10" "Skipping optional Data SSD and SMB setup..."
    notice "/data is not mounted read/write. Docker uses the normal system storage path; Data SSD setup can be rerun after /data is mounted."
fi

echo
echo "Installed versions:"
echo "  Git:       $(git --version)"
echo "  Ghostty:   $(ghostty --version | head -n 1)"
echo "  VS Code:   $(code --version | head -n 1)"
echo "  fzf:       $(fzf --version | awk '{ print $1 }')"
echo "  Zsh:       $(zsh --version)"
echo "  tmux:      $(tmux -V)"
echo "  Docker:    $(docker --version)"
echo "  Compose:   $(docker compose version)"
if command -v sqlcmd > /dev/null 2>&1; then
    echo "  sqlcmd:    installed"
else
    echo "  sqlcmd:    not installed"
fi
echo "  .NET SDKs:"
dotnet --list-sdks | sed 's/^/    /'
echo "  mise:      $(mise --version | head -n 1)"
echo "  Node.js:   $(node --version)"
echo "  npm:       $(npm --version)"
echo "  Yarn:      $(yarn --version)"
echo "  Angular:   $(ng version 2>/dev/null | awk '/Angular CLI:/ { print $3; exit }')"
echo "  Codex CLI: $(codex --version 2>/dev/null || echo unavailable)"
echo "  Claude:    $(claude --version 2>/dev/null || echo unavailable)"
echo "  Copilot:   $(copilot --version 2>/dev/null || echo unavailable)"

echo
echo "========================================="
echo " Omarchy Forge bootstrap completed."
echo "========================================="
echo
echo "Run 'exec zsh' to load the Forge aliases and prompt."
echo "Run 'docker-on' to start Docker on demand."
echo "Place forge-secrets.sh in ${FORGE_CONFIG_HOME} before using Forge SQL commands."
