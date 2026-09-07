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

- `inf` (`scripts/info.sh`) intentionally reports no CPU temperature/thermal row. Two paths were
  tried and abandoned in 2026-09:
  - `smctemp` (numeric-Celsius CLI, no sudo needed): uninstalled, its tap removed. It reproducibly
    got "stuck" echoing a flat, wrong ~40.0°C as a valid-looking success for several seconds after
    any failed sensor query, indistinguishable from a real reading by exit code or sanity range —
    no script-side retry/averaging strategy could tell a stuck 40 from a genuine one.
  - `sudo powermetrics --samplers thermal` (Apple's qualitative Nominal/Fair/Serious/Critical
    pressure level): worked and was live-verified as non-fake, but stayed "Nominal" through 90s of
    sustained heavy load that pushed the raw die sensor to 85-92°C earlier the same session — it
    only escalates when macOS is actually throttling, not with felt/measured heat, so it carries
    essentially no useful signal for this machine's cooling headroom. The one-time sudoers rule
    that made it passwordless (`/etc/sudoers.d/mac-forge-powermetrics-thermal`) has been removed.
  - Do not reinstall smctemp or re-add the sudoers rule for this purpose without re-verifying both
    behaviors first; the underlying `smc` sampler in `powermetrics` is also gone from this macOS
    version entirely (absent from `sudo powermetrics -h`'s supported list, root included), so no
    numeric-Celsius path is currently known to be reliable via any legitimate userspace tool.
