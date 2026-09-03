# Operations and Remote Server Hygiene

Apply these project-agnostic rules to deployments, provisioning, remote-server work, and
Docker-hosted database operations, including vps1.

## Docker Database Routing

- VPS1 is the default Docker-hosted development database for Hades, Cerber, and MasterChief. Use the
  established private connection, tunnel, and client helpers for the active station; never expose or
  hardcode connection secrets.
- Do not select a local SQL container merely because local Docker is available. Hades local SQL is a
  contingency only when Oliver explicitly requests it, or VPS1 connectivity is verified unavailable
  and Oliver confirms changing database targets.
- Only for that contingency, load
  `~/.config/ai/guidelines/stacks/docker-db-local-fallback.md`. Do not read it for normal VPS1 work.
- This routing governs Docker-hosted databases only. Local image builds, application containers,
  Compose, and unrelated Docker cleanup remain local when the task requires them.

## Remote Temporary Artifacts

- Track every temporary artifact created remotely: staged scripts, uploaded helpers, `/tmp` files,
  scratch logs, ad-hoc backups, and other one-off files outside the permanent deployment.
- At task completion or abandonment, remove every temporary artifact introduced. Preserve required
  release artifacts, service `deploy/` scripts, systemd units, environment files, and runtime
  configuration.
- Stage temporary files in a predictable, easy-to-purge location with a clear project-prefixed name,
  such as `/tmp/tally-...`.
- Verify cleanup by listing the relevant directory or name pattern; do not assume deletion succeeded.
- If a temporary file must intentionally remain, tell the user its location and why.

## Safe Remote Changes

- Before editing server configuration, create a timestamped backup. Validate the new configuration
  before reloading the service, such as `caddy validate` before `systemctl reload caddy`.
- Prefer idempotent change scripts so rerunning after a partial failure is safe.
- After every privileged step, verify the end state through the relevant service status, health
  endpoint, or public URL.
