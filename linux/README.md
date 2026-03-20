# Linux Fresh Install Checklist

A list of essential tools and configurations for a fresh Linux installation.

## Window Management
- **i3 tiling manager**: Efficient keyboard-driven window management. (Under investigation)

## Utilities
- **Flameshot**: Powerful screenshot tool.
    - *Note: Add the following to `~/.config/i3/config`:*
      ```bash
      # choice for screenshot screen
      bindsym Print exec flameshot gui -c
      ```

## SSH & Shell Configuration
- **SSH Agent**: Automatically start the agent and add keys in `~/.zshrc`:
  ```bash
  # Make sure the ssh keys are in
  # Start ssh-agent if not running
  if ! pgrep -u "$USER" ssh-agent > /dev/null; then
    eval "$(ssh-agent -s)" > /dev/null
  fi

  # Add keys if not already added
  ssh-add -l >/dev/null 2>&1 || ssh-add ~/.ssh/id_ed25519_ardis ~/.ssh/id_ed25519_github
  ```
