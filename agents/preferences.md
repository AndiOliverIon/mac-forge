# Preferences scope

Read this file when the task involves machine setup, tool installation, operator preferences, or Hades-specific environment choices.

## Operator and machine context

- The primary operator is Andi Ion Oliver, working mainly from `Hades` on macOS.
- Default technical context is .NET, SQL, and web development in a personal operations workspace.
- Work with the user as a practical partner: optimize for directness, useful action, and minimal friction.

## Setup preferences

- When installing or documenting .NET SDK setup for this machine, prefer Microsoft installers over Homebrew.
- When installing or documenting VPN setup for this machine, prefer FortiClient VPN only, not the full Fortinet suite.
- Preserve the existing Forge workflow for switching SQL storage locations unless the user explicitly asks to redesign it.

## Hades-specific environment dependencies

- `inf`'s Thermal row (`scripts/info.sh`, `cpu_thermal_pressure`) calls `sudo -n powermetrics
  --samplers thermal -i200 -n1`, which needs a passwordless sudoers rule scoped to that exact
  command: `/etc/sudoers.d/mac-forge-powermetrics-thermal` containing
  `oliver ALL=(root) NOPASSWD: /usr/bin/powermetrics --samplers thermal -i200 -n1`. That file lives
  outside this repo (not tracked in git) and outside Forge's own config; without it the Thermal row
  silently reads "Unavailable" (sudo fails fast via `-n`, no hang). If reinstating on a fresh Hades
  setup or another station, recreate it with `sudo visudo -f /etc/sudoers.d/mac-forge-powermetrics-thermal`
  (or `echo ... | sudo tee ... && sudo chmod 440 ...`), then `sudo visudo -c` to validate.
- `smctemp` (a numeric-Celsius CPU temp CLI, formerly used for this same row) was uninstalled and
  its tap removed: it reproducibly got "stuck" echoing a flat, wrong ~40.0°C as a valid-looking
  success for several seconds after any failed sensor query, with no reliable script-side way to
  detect it. Do not reinstall it for this purpose without re-verifying that behavior first.
