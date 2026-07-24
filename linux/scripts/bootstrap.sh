#!/usr/bin/env bash

set -euo pipefail

NVM_VERSION="v0.40.6"
ANGULAR_CLI_VERSION="20.3.16"
YARN_VERSION="1.22.22"
NVM_DIR="${HOME}/.nvm"
DOTNET_INSTALL_DIR="/usr/share/dotnet"
FORGE_ROOT="${FORGE_ROOT:-$HOME/mac-forge}"
export PATH="${HOME}/.local/bin:${PATH}"

step() {
    echo
    echo "[$1] $2"
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
        echo "NOTICE: Telerik license was not found."
        echo "Place .telerik/telerik-license.txt in the launch directory or /data/forge-temp,"
        echo "then rerun the bootstrap. TELERIK_LICENSE_SOURCE_DIR can override the source."
    fi
}

echo "========================================="
echo " Ubuntu Forge Bootstrap"
echo "========================================="

step "1/18" "Updating package index..."
sudo apt update

step "2/18" "Upgrading installed packages..."
sudo apt full-upgrade -y

step "3/18" "Removing unused packages..."
sudo apt autoremove -y
sudo apt autoclean

step "4/18" "Installing essential tools..."
sudo apt install -y \
    ca-certificates \
    git \
    gpg \
    curl \
    wget \
    unzip \
    zip \
    tree \
    htop \
    btop \
    fzf \
    jq \
    lsof \
    netcat-openbsd \
    openconnect \
    openssh-client \
    xdg-utils \
    acl \
    zsh \
    build-essential \
    snapd \
    software-properties-common

step "5/18" "Installing Visual Studio Code..."
wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
    | sudo gpg --dearmor --yes -o /usr/share/keyrings/microsoft.gpg
sudo chmod 644 /usr/share/keyrings/microsoft.gpg

sudo tee /etc/apt/sources.list.d/vscode.sources > /dev/null <<'EOF'
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/microsoft.gpg
EOF

sudo apt update
sudo apt install -y code

step "6/18" "Installing JetBrains Rider..."
if ! snap list rider > /dev/null 2>&1; then
    sudo snap install rider --classic
fi

step "7/18" "Installing .NET 8, .NET 9, and .NET 10 SDKs system-wide..."
dotnet_installer="$(mktemp)"
trap 'rm -f "${dotnet_installer}"' EXIT
curl -fsSL https://dot.net/v1/dotnet-install.sh -o "${dotnet_installer}"
chmod +x "${dotnet_installer}"

sudo mkdir -p "${DOTNET_INSTALL_DIR}"
sudo "${dotnet_installer}" \
    --channel 8.0 \
    --quality GA \
    --install-dir "${DOTNET_INSTALL_DIR}" \
    --no-path
sudo "${dotnet_installer}" \
    --channel 9.0 \
    --quality GA \
    --install-dir "${DOTNET_INSTALL_DIR}" \
    --no-path
sudo "${dotnet_installer}" \
    --channel 10.0 \
    --quality GA \
    --install-dir "${DOTNET_INSTALL_DIR}" \
    --no-path
sudo ln -sfn "${DOTNET_INSTALL_DIR}/dotnet" /usr/bin/dotnet

rm -f "${dotnet_installer}"
trap - EXIT

step "8/18" "Installing or updating NVM..."

if [ ! -d "${NVM_DIR}/.git" ]; then
    git clone https://github.com/nvm-sh/nvm.git "${NVM_DIR}"
fi

(
    cd "${NVM_DIR}"
    git fetch --tags --quiet
    git checkout "${NVM_VERSION}"
)

# Load NVM in the current script.
export NVM_DIR
# shellcheck disable=SC1091
[ -s "${NVM_DIR}/nvm.sh" ] && . "${NVM_DIR}/nvm.sh"

# Ensure NVM loads automatically in future terminal sessions.
if ! grep -q 'export NVM_DIR="$HOME/.nvm"' "${HOME}/.bashrc"; then
    cat >> "${HOME}/.bashrc" <<'EOF'

# NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
EOF
fi

step "9/18" "Installing the latest Node.js LTS release..."
nvm install --lts
nvm use --lts
nvm alias default 'lts/*'
nvm install-latest-npm

step "10/18" "Installing global npm development tools..."
npm install --global @openai/codex
npm install --global "@angular/cli@${ANGULAR_CLI_VERSION}"
corepack enable
corepack install --global "yarn@${YARN_VERSION}"

step "11/18" "Configuring the Telerik license..."
install_telerik_license

step "12/18" "Installing or updating Claude Code..."
curl -fsSL https://claude.ai/install.sh | bash

step "13/18" "Installing or updating GitHub Copilot CLI..."
curl -fsSL https://gh.io/copilot-install | bash

step "14/18" "Installing and configuring Ghostty..."
sudo apt install -y ghostty

GHOSTTY_CONFIG_DIR="${HOME}/.config/ghostty"
GHOSTTY_CONFIG="${GHOSTTY_CONFIG_DIR}/config.ghostty"
mkdir -p "${GHOSTTY_CONFIG_DIR}"
ln -sfn "${FORGE_ROOT}/linux/config/ghostty.ghostty" "${GHOSTTY_CONFIG}"

# Reserve Ctrl+Alt+Arrow for Ghostty split navigation.
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-left \
    "['<Super>Page_Up', '<Super>KP_Prior', '<Super><Alt>Left']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-right \
    "['<Super>Page_Down', '<Super>KP_Next', '<Super><Alt>Right']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-up "[]"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-down "[]"

step "15/18" "Installing Oh My Zsh and Powerlevel10k..."
if [ ! -d "${HOME}/.oh-my-zsh/.git" ]; then
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
        "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
        "" --unattended
fi

POWERLEVEL10K_DIR="${HOME}/.oh-my-zsh/custom/themes/powerlevel10k"
if [ ! -d "${POWERLEVEL10K_DIR}/.git" ]; then
    git clone --depth=1 \
        https://github.com/romkatv/powerlevel10k.git \
        "${POWERLEVEL10K_DIR}"
fi

if grep -q '^ZSH_THEME=' "${HOME}/.zshrc"; then
    sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "${HOME}/.zshrc"
else
    printf '\nZSH_THEME="powerlevel10k/powerlevel10k"\n' >> "${HOME}/.zshrc"
fi

if ! grep -q 'export NVM_DIR="$HOME/.nvm"' "${HOME}/.zshrc"; then
    cat >> "${HOME}/.zshrc" <<'EOF'

# NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
EOF
fi

"${FORGE_ROOT}/linux/scripts/link-dotfiles.sh"

step "16/18" "Preparing the permanent Data SSD layout..."
sudo "${FORGE_ROOT}/linux/scripts/setup-data-layout.sh"

mkdir -p "${HOME}/work"

step "17/18" "Installing and configuring Docker Engine..."
sudo "${FORGE_ROOT}/linux/scripts/install-docker.sh"

step "18/18" "Sharing /data over SMB..."
sudo "${FORGE_ROOT}/linux/scripts/install-data-share.sh"

sudo chsh -s "$(command -v zsh)" "${USER}"

echo
echo "Installed versions:"
echo "  Git:       $(git --version)"
echo "  VS Code:   $(code --version | head -n 1)"
echo "  Rider:     $(snap list rider | awk 'NR == 2 { print $2 }')"
echo "  Ghostty:   $(ghostty --version | head -n 1)"
echo "  fzf:       $(fzf --version | awk '{ print $1 }')"
echo "  Zsh:       $(zsh --version)"
echo "  Docker:    $(docker --version)"
echo "  Compose:   $(docker compose version)"
echo "  .NET SDKs:"
dotnet --list-sdks | sed 's/^/    /'
echo "  NVM:       $(nvm --version)"
echo "  Node.js:   $(node --version)"
echo "  npm:       $(npm --version)"
echo "  Yarn:      $(yarn --version)"
echo "  Angular:   $(ng version 2>/dev/null | awk '/Angular CLI:/ { print $3; exit }')"
echo "  Codex CLI: $(codex --version)"
echo "  Claude:    $(claude --version)"
echo "  Copilot:   $(copilot --version)"

echo
echo "========================================="
echo " Bootstrap completed successfully."
echo "========================================="
echo
echo "Run 'codex' to authenticate and start Codex CLI."
echo "Run 'claude' to authenticate and start Claude Code."
echo "Run 'copilot' and enter '/login' to authenticate GitHub Copilot CLI."
echo "Run 'exec zsh' to load the shared macOS-master Powerlevel10k profile."
echo "Run 'sudo smbpasswd -a ${USER}' to set the Data share password."
echo "Place forge-secrets.sh in /data/forge before using Forge SQL commands."
