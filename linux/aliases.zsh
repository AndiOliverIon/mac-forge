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
alias help="~/mac-forge/scripts/help.sh"
alias codex-local-register="bash ~/mac-forge/linux/scripts/codex-local-register.sh"
alias ai-config="~/mac-forge/scripts/ai-config.sh"
alias ai-verify="~/mac-forge/scripts/ai-config.sh verify"
alias ai-install="~/mac-forge/scripts/ai-config.sh install"
alias link-dotfiles="~/mac-forge/linux/scripts/link-dotfiles.sh"
alias ldf=link-dotfiles
alias verify-workstation="~/mac-forge/linux/scripts/verify-workstation.sh"
alias vw=verify-workstation
alias inf="clear && ~/mac-forge/linux/scripts/inf.sh"
alias web="~/mac-forge/scripts/web.sh"
alias ftp="~/mac-forge/scripts/ftp.sh"
alias vpn="~/mac-forge/scripts/vpn.sh"
alias dvpn="~/mac-forge/scripts/dvpn.sh"
alias vpns="~/mac-forge/scripts/vpn-status.sh"
alias sim="~/mac-forge/linux/scripts/sim.sh"
alias ardis-patch="~/mac-forge/linux/scripts/patch.sh"
alias ap="ardis-patch"
alias patch="~/mac-forge/linux/scripts/patch.sh"
alias p=patch
alias pr="patch -R"
alias convert-mov="~/mac-forge/scripts/convert-mov.sh"
alias genopenapi="~/mac-forge/linux/scripts/gen-open-api.sh"
alias goa=genopenapi
alias genopenapitimetrack="~/mac-forge/scripts/gen-open-api-timetrack.sh"

# ------------------------------------------------------------------------------
# Git Shortcuts
# ------------------------------------------------------------------------------
alias aiusage='~/mac-forge/scripts/agents/usage.sh'
alias gs="git status"
alias gco="git checkout"
alias gp="git pull"
alias gfo="git fetch origin"
alias gpu="git push"
alias gpo="~/mac-forge/scripts/git-publish-origin.sh"
alias peer-fetch="~/mac-forge/scripts/git-peer-fetch.sh"
alias h2mc="~/mac-forge/scripts/git-peer-fetch.sh hades work"
alias h2r="~/mac-forge/scripts/git-peer-fetch.sh hades raynor"
alias h2z="~/mac-forge/scripts/git-peer-fetch.sh hades zeratul"
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
alias docker-on="~/mac-forge/linux/scripts/docker-on.sh"
alias don=docker-on
alias dps="docker ps"
alias dcu="docker compose up"
alias dcd="docker compose down"
alias docker-clean-fact="~/mac-forge/scripts/docker-clean-known-facts.sh"
alias dcf=docker-clean-fact

# ------------------------------------------------------------------------------
# Database Scripts
# ------------------------------------------------------------------------------
alias dblist="~/mac-forge/linux/scripts/db-list.sh"
alias dbr="~/mac-forge/linux/scripts/db-restore.sh"
alias dbrf="~/mac-forge/linux/scripts/db-restore-files.sh"
alias dbsn="~/mac-forge/linux/scripts/db-snapshot.sh"
alias rdbsn="~/mac-forge/scripts/db-remote-backup.sh"
alias rdown="~/mac-forge/linux/scripts/db-remote-download.sh"
alias dbo="~/mac-forge/scripts/db-optimize.sh"
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
case "${FORGE_AGENT_IDENTITY:-}:${FORGE_UNIVERSE_ROOT:-}" in
  raynor:/home/oliver/raynor | zeratul:/home/oliver/zeratul)
    export FORGE_WORK_ROOT="$FORGE_UNIVERSE_ROOT"
    ;;
  *)
    export FORGE_WORK_ROOT="$HOME/work"
    ;;
esac
alias workspace-primary="~/mac-forge/linux/scripts/load-workspace.sh"
alias wp=workspace-primary
alias data="cd /data"
alias dock="cd /data/docker"
alias work='cd "$FORGE_WORK_ROOT"'
alias perf='cd "$FORGE_WORK_ROOT/ardis-perform"'
alias perf230='cd "$FORGE_WORK_ROOT/ardis-perform-230"'
alias timetrack='cd "$FORGE_WORK_ROOT/ardis.timetrack"'
alias tt=timetrack
alias ttbs='cd "$FORGE_WORK_ROOT/ardis.timetrack" && ./buildsolution.sh'
alias ttbd='cd "$FORGE_WORK_ROOT/ardis.timetrack" && ./Ardis.Timetrack/build-docker.sh'
alias ttc='cd "$FORGE_WORK_ROOT/ardis.timetrack/ardis.timetrack.client"'
alias ttclient='cd "$FORGE_WORK_ROOT/ardis.timetrack/ardis.timetrack.client"'
alias ttmd='cd "$FORGE_WORK_ROOT/ardis.timetrack/Ardis.Timetrack.Migrations/Database"'
alias perfclient='cd "$FORGE_WORK_ROOT/ardis-perform/ardis.perform.client"'
alias perfdev='cd "$FORGE_WORK_ROOT/ardis-perform-dev"'
alias perfold='cd "$FORGE_WORK_ROOT/ardis-perform-older"'
alias gpt='cd "$FORGE_WORK_ROOT/ardis.tools.extensions"'
alias gptbin='cd "$FORGE_WORK_ROOT/ardis.tools.extensions/Ardis.Utils/bin/debug/net8.0"'
alias lc='cd "$FORGE_WORK_ROOT/ardis-local-connector"'
alias localconnector='cd "$FORGE_WORK_ROOT/ardis-local-connector"'
alias meerkat="cd ~/projects/meerkat"
alias rooted="cd ~/projects/rooted"
alias aiwk="cd /Users/oliver/projects/alice-in-wonderkitchen"
alias wk="cd ~/projects/alice-in-wonderkitchen"
alias wkdata="cd ~/projects/alice-in-wonderkitchen/wonderkitchen-data"
alias dwkdata="/Users/oliver/mac-forge/scripts/deploy-wonderkitchen.sh"

# ------------------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------------------
alias linux-clean="~/mac-forge/linux/scripts/linux-clean.sh"
alias dela="rm -rf ./*"

# ------------------------------------------------------------------------------
# Remote & Network
# ------------------------------------------------------------------------------
alias display="~/mac-forge/linux/scripts/setup-display.sh"
alias disp="~/mac-forge/linux/scripts/disp.sh"
alias mnt='~/mac-forge/linux/scripts/mount.sh'
alias mnthadesw='~/mac-forge/linux/scripts/hades-mount.sh'
alias mnthw=mnthadesw
alias umnthadesw='~/mac-forge/linux/scripts/hades-umount.sh'
alias umnthw=umnthadesw
alias hades-tunnel-up='~/mac-forge/linux/scripts/hades-tunnel.sh up'
alias hades-tunnel-down='~/mac-forge/linux/scripts/hades-tunnel.sh down'
alias hades-tunnel-status='~/mac-forge/linux/scripts/hades-tunnel.sh status'
alias htu=hades-tunnel-up
alias htd=hades-tunnel-down
alias raynor="~/mac-forge/scripts/masterchief-agent-session.sh raynor"
alias zeratul="~/mac-forge/scripts/masterchief-agent-session.sh zeratul"
alias rmc="ssh -t oliver@masterchief"
alias rmcr="ssh -t oliver@masterchief-ts"
alias mcshutdown='ssh -t oliver@masterchief "sudo systemctl poweroff"'
alias mcsleep='~/mac-forge/scripts/mcsleep.sh'
alias ms=mcsleep

alias mcboot='~/mac-forge/scripts/mcboot.sh'
alias mcbt=mcboot

# ------------------------------------------------------------------------------
# zoxide & yazi
# ------------------------------------------------------------------------------
# zoxide: smarter cd (adds `z` and `zi`)
# Ensure ~/.local/bin is on PATH first: this file may be sourced before
# ~/.zshrc adds it, which would otherwise hide the zoxide binary.
[[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || export PATH="$HOME/.local/bin:$PATH"
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"

# yazi: `y` opens the file manager and cd's to the last dir on exit
function y() {
	local tmp="$(mktemp -t yazi-cwd.XXXXXX)" cwd
	yazi "$@" --cwd-file="$tmp"
	if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
		builtin cd -- "$cwd"
	fi
	rm -f -- "$tmp"
}
