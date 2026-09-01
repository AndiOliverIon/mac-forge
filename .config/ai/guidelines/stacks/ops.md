# Coding Guidelines — Operations and Remote Server Hygiene

> Generic, project-agnostic rules for deploys, provisioning, and any work touching remote
> servers (e.g. vps1). Intended as a living reference.

---

## 1. Remote Temporary-Artifact Cleanup (vps1 and any remote host)

The server must be kept tidy and on a green, functional state. Do not leave junk behind.

- **Track every temporary artifact you create on a remote host.** This includes staged
  scripts, uploaded helpers, `/tmp` files, scratch logs, ad-hoc backups you created, and any
  one-off file that is not a permanent part of the deployment.
- **Clean them up at task closure.** Once the task is complete (or abandoned), remove every
  temporary artifact you introduced. The host should be left with only the files it is meant
  to keep permanently.
- **Keep permanent deployment files.** Released build artifacts, deploy scripts under the
  service's own `deploy/` directory, systemd units, env files, and config the server needs to
  run are NOT temporary — do not delete these.
- **Prefer staging temporaries in a predictable, easy-to-purge location** (e.g. `/tmp` with a
  clear, project-prefixed name like `tally-...`) so cleanup is unambiguous.
- **Verify the cleanup.** After removing, confirm nothing is left (e.g. list the directory or
  the name pattern) rather than assuming the delete succeeded.
- **If a temporary must intentionally survive** the task (rare), say so explicitly to the user
  and note where it lives and why, so it is a deliberate decision rather than forgotten junk.

This rule is mandatory: never raise junk on a remote host that must stay tidy and functional.

---

## 2. Safe Remote Changes

- Back up any existing server config before editing it (timestamped backup), and validate
  before reloading the service (e.g. `caddy validate` before `systemctl reload caddy`).
- Make idempotent change scripts where possible, so a re-run after a partial failure is safe.
- Verify the end state after every privileged step (service `is-active`, health endpoint,
  public URL) rather than assuming success.
