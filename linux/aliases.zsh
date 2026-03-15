# Linux aliases for the shared mac-forge workspace.
# Keep this file focused on aliases that are useful on Linux today.

# ------------------------------------------------------------------------------
# Core Navigation
# ------------------------------------------------------------------------------
alias oliver="cd ~/"
alias doc="cd ~/Documents"
alias desk="cd ~/Desktop"
alias dev="cd ~/dev"
alias down="cd ~/Downloads"
alias projects="cd ~/projects"
alias reloadterm="source ~/.zshrc"

# ------------------------------------------------------------------------------
# mac-forge
# ------------------------------------------------------------------------------
alias forge="cd ~/mac-forge"
alias aliases="sed -n '1,240p' ~/mac-forge/linux/aliases.zsh"
alias link-dotfiles="~/mac-forge/linux/scripts/link-dotfiles.sh"
alias ldf=link-dotfiles

# ------------------------------------------------------------------------------
# Git Shortcuts
# ------------------------------------------------------------------------------
alias gs="git status"
alias gco="git checkout"
alias gp="git pull"
alias gfo="git fetch origin"
alias gpu="git push"
alias gb="git branch"
alias switch="~/mac-forge/scripts/git-switch.sh"
alias sw=switch
alias gbd="~/mac-forge/scripts/branch-delete.sh"
alias gdel="~/mac-forge/scripts/git-del.sh"
alias branch-clean="~/mac-forge/scripts/branch-local-clean.sh"
alias bc=branch-clean

# ------------------------------------------------------------------------------
# Docker
# ------------------------------------------------------------------------------
alias dps="docker ps"
alias dcu="docker compose up"
alias dcd="docker compose down"

# ------------------------------------------------------------------------------
# Workspaces & Paths
# ------------------------------------------------------------------------------
alias work="cd ~/work"
alias perf="cd ~/work/ardis-perform"
alias perfclient="cd ~/work/ardis-perform/ardis.perform.client"
alias gpt="cd ~/work/ardis.tools.extensions"
alias gptbin="cd ~/work/ardis.tools.extensions/Ardis.Utils/bin/debug/net8.0"
alias lc="cd ~/work/ardis-local-connector"
alias localconnector="cd ~/work/ardis-local-connector"

# ------------------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------------------
alias dela="rm -rf ./*"

# ------------------------------------------------------------------------------
# Remote & Network
# ------------------------------------------------------------------------------
alias mnthadesw='~/mac-forge/linux/scripts/hades-mount.sh'
alias mnthw=mnthadesw
alias umnthadesw='~/mac-forge/linux/scripts/hades-umount.sh'
alias umnthw=umnthadesw
alias rmc="ssh -t oliver@masterchief"
alias rth="ssh -t oliver@thanatos"
alias rt=rth
alias mcshutdown='ssh -t oliver@masterchief "cmd /c shutdown /s /f /t 0"'
