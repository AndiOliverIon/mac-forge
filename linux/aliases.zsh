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
__kp() {
  if [[ -z "${1:-}" ]]; then
    echo "Usage: kp <port>" >&2
    return 2
  fi

  kill $(lsof -ti tcp:"$1")
}
alias kp=__kp

# ------------------------------------------------------------------------------
# mac-forge
# ------------------------------------------------------------------------------
alias forge="cd ~/mac-forge"
alias aliases="sed -n '1,240p' ~/mac-forge/linux/aliases.zsh"
alias link-dotfiles="~/mac-forge/linux/scripts/link-dotfiles.sh"
alias ldf=link-dotfiles
alias inf="~/mac-forge/linux/scripts/inf.sh"
alias ardis-patch="~/mac-forge/linux/scripts/patch.sh"
alias ap="ardis-patch"
alias patch="~/mac-forge/linux/scripts/patch.sh"
alias p=patch
alias pr="patch -R"
alias convert-mov="~/mac-forge/scripts/convert-mov.sh"

# ------------------------------------------------------------------------------
# Git Shortcuts
# ------------------------------------------------------------------------------
unalias g 2>/dev/null
alias g="gemini"
alias aiusage='~/mac-forge/scripts/agents/usage.sh'
alias gs="git status"
alias gco="git checkout"
alias gp="git pull"
alias gfo="git fetch origin"
alias gpu="git push"
alias gpo="~/mac-forge/scripts/git-publish-origin.sh"
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
# Database Scripts
# ------------------------------------------------------------------------------
alias dbr="~/mac-forge/linux/scripts/db-restore.sh"
alias dbsn="~/mac-forge/linux/scripts/db-snapshot.sh"
alias ardis-migrate="~/mac-forge/linux/scripts/ardis-migrate.sh"
alias am="ardis-migrate"
alias publish-tt="~/mac-forge/scripts/publish-tt.sh"
alias publish-te="~/mac-forge/scripts/publish-te.sh"
alias publish-perf-local="~/mac-forge/scripts/perform-local-portainer.sh --interactive --compose-up"
alias script-run="~/mac-forge/scripts/script-run.sh"
alias sr=script-run

# ------------------------------------------------------------------------------
# Workspaces & Paths
# ------------------------------------------------------------------------------
alias workspace-primary="~/mac-forge/linux/scripts/load-workspace.sh"
alias wp=workspace-primary
alias work="cd ~/work"
alias perf="cd ~/work/ardis-perform"
alias timetrack="cd ~/work/ardis.timetrack"
alias tt=timetrack
alias ttbs="cd ~/work/ardis.timetrack && ./buildsolution.sh"
alias ttbd="cd ~/work/ardis.timetrack && ./Ardis.Timetrack/build-docker.sh"
alias ttc="cd ~/work/ardis.timetrack/ardis.timetrack.client"
alias ttclient="cd ~/work/ardis.timetrack/ardis.timetrack.client"
alias ttmd="cd ~/work/ardis.timetrack/Ardis.Timetrack.Migrations/Database"
alias perfclient="cd ~/work/ardis-perform/ardis.perform.client"
alias perfdev="cd ~/work/ardis-perform-dev"
alias gpt="cd ~/work/ardis.tools.extensions"
alias gptbin="cd ~/work/ardis.tools.extensions/Ardis.Utils/bin/debug/net8.0"
alias lc="cd ~/work/ardis-local-connector"
alias localconnector="cd ~/work/ardis-local-connector"
alias meerkat="cd ~/projects/meerkat"
alias aiwk="cd /Users/oliver/projects/alice-in-wonderkitchen"
alias wk="cd ~/projects/alice-in-wonderkitchen"
alias wkdata="cd ~/projects/alice-in-wonderkitchen/wonderkitchen-data"
alias dwkdata="/Users/oliver/mac-forge/scripts/deploy-wonderkitchen.sh"

# ------------------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------------------
alias dela="rm -rf ./*"

# ------------------------------------------------------------------------------
# Remote & Network
# ------------------------------------------------------------------------------
alias display="~/mac-forge/linux/scripts/setup-display.sh"
alias mnthadesw='~/mac-forge/linux/scripts/hades-mount.sh'
alias mnthw=mnthadesw
alias umnthadesw='~/mac-forge/linux/scripts/hades-umount.sh'
alias umnthw=umnthadesw
alias rmc="ssh -t oliver@masterchief"
alias rmcr="ssh -t oliver@masterchief-ts"
alias rth="ssh -t oliver@thanatos"
alias rthr="ssh -t oliver@thanatos-ts"
alias rt=rth
alias mcshutdown='ssh -t oliver@masterchief "powershell -Command \"Stop-Computer -Force\""'
alias thshutdown='ssh -t oliver@thanatos "powershell -Command \"Stop-Computer -Force\""'
alias tsshutdown=thshutdown
alias mcsleep='~/mac-forge/scripts/mcsleep.sh'
alias ms=mcsleep
alias tssleep='~/mac-forge/scripts/thsleep.sh'
alias thsleep=tssleep
alias ts=tssleep
alias tshut=thshutdown
alias thshut=thshutdown

alias mcboot='~/mac-forge/scripts/mcboot.sh'
alias mcbt=mcboot
alias thboot='~/mac-forge/scripts/thboot.sh'
alias tboot=thboot
alias thbt=thboot
