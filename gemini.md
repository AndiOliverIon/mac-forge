# Gemini Workspace Documentation

This document serves as the primary context for the Gemini AI agent when working within the `mac-forge` repository. It consolidates user preferences, system architecture, and script documentation.

## 1. User Persona & Context

*   **User Name:** Andi Ion Oliver
*   **Emails:** `andioliverion@gmail.com` (Personal), `andi@ardis.eu` (Work)
*   **Workstation:** "Hades" (macOS)
*   **Role:** Software Engineer (focus on .NET/SQL/Web)
*   **Key Philosophy:** "Partner" relationship with AI.
*   **Critical Preferences:**
    *   **Dotnet:** Install SDKs via Microsoft installers, *not* Homebrew (avoids compiler issues).
    *   **VPN:** Install *only* FortiClient VPN (no full suite).
    *   **Docker:** Uses a custom "Forge" setup to switch SQL data locations (Local/External/Network).

## 2. Project Architecture

`mac-forge` is a central automation hub. Its primary goal is to abstract away the complexity of managing SQL Server on macOS (via Docker) and to provide shortcuts for daily development tasks (Ardis/Perform projects).

### Core Components

*   **`scripts/forge.sh`**: The "Kernel". This script is sourced by almost all other scripts. It:
    *   Sets environment variables (`FORGE_SQL_USER`, `FORGE_SQL_PORT`).
    *   Reads `configs/work-state.json` to determine *active* storage paths.
    *   Defines paths for the "Ardis" project.
*   **`configs/work-state.json`**: The "State". Defines where the Docker container should look for data *right now*.
    *   `docker-path`: Host path for SQL data (bind-mounted).
    *   `docker-snapshot-path`: Host path for `.bak` files.

## 3. Key Workflows & Scripts

### Ardis / Perform Development (Work)

These scripts are specific to the user's employment at Ardis.

*   **`scripts/perform-prep.sh [Config]`**
    *   **Purpose:** Prepares the `Asms2.Web` project for local execution.
    *   **Critical Action:** Copies `libgdiplus.dylib` (from Homebrew/System) into the project's `bin/...` directory. This resolves `System.Drawing` errors on macOS.
    *   **Usage:** `scripts/perform-prep.sh` (Defaults to `DebugUnitTestLocal`).

*   **`scripts/ardis-migrate.sh`**
    *   **Purpose:** Interactive tool to apply database migrations.
    *   **Flow:**
        1.  Builds `Ardis.Migrations.Console`.
        2.  Checks if `forge-sql` container is running.
        3.  Uses `fzf` to let the user select a target database from the container.
        4.  Runs the migration tool against that DB.

### Database & Docker (The "Forge" System)

The user employs a specific cyclical workflow for database management: **Restore -> Work -> Scrap**.
1.  **Restore:** A development or client database is restored into the Docker container.
2.  **Work:** The user performs tasks, runs migrations, or debugs against this instance.
3.  **Scrap:** The database is completely removed/cleared to prepare for the next task.

The user runs SQL Server 2022 in a Docker container named `forge-sql` on port `2022`.

*   **`scripts/docker-start.sh`**: Starts the `forge-sql` container using paths defined in `work-state.json`.
*   **`scripts/db-restore.sh`**: Restores a database from a snapshot (The "Restore" phase).
*   **`scripts/db-snapshot.sh`**: Creates a backup (`.bak`) of a database (optional, for saving intermediate state).
*   **`scripts/db-clear.sh`**: Implements the "Scrap" phase.
    *   **Default (Hard):** Stops/Removes container and wipes data (preserving snapshots).
    *   **`--soft`:** Drops all user databases but keeps the container running.
*   **`scripts/db-admin.sh`**: Launches a DB management tool (likely Azure Data Studio or similar, depending on alias).

### System Maintenance

*   **`scripts/organizer.sh`**: Moves files from Downloads/Desktop into categorized folders (Images, Archives, SQL, etc.) defined in `configs/work-state.json`.
*   **`scripts/win-shortcut-clean.sh`**: Removes the Windows app shortcuts that Parallels creates in the macOS Launchpad.
*   **`scripts/forge.sh` Secrets**: Looks for secrets in `$HOME/Library/Mobile Documents/com~apple~CloudDocs/forge/forge-secrets.sh`.

## 4. Configuration Reference

### `configs/work-state.json` Schema
```json
{
  "docker-path": "/current/active/path/to/sql/data",
  "docker-snapshot-path": "/current/active/path/to/snapshots",
  "docker-locations": [ ... list of known locations (Local, Acasis, etc.) ... ],
  "organize-categories": [ ... file extension rules ... ]
}
```

### Important Environment Variables (Exported by `forge.sh`)
*   `FORGE_SQL_DOCKER_CONTAINER`: `forge-sql`
*   `FORGE_SQL_PORT`: `2022`
*   `FORGE_SQL_USER`: `sa`
*   `ARDIS_MIGRATIONS_PATH`: `$HOME/work/ardis-perform/Ardis.Migrations.Console`

## 5. Quick Checklist for AI Agent
1.  **Context:** Always check `configs/work-state.json` if debugging Docker/path issues.
2.  **Safety:** Do not overwrite `configs/work-state.json` manually unless instructed; it's likely managed by `work.sh`.
3.  **Secrets:** Never output the contents of `forge-secrets.sh`.

## 6. Git & Repository Operations

To maintain the integrity of this repository, the following rules apply:
*   **No Auto-Commits:** Never `git commit`, `git push`, `git reset`, or `git stash` unless explicitly instructed by the user.
*   **Context Discovery:** You are encouraged to use read-only commands (`git log`, `git diff`, `git show`, `git status`) to understand recent changes, commit patterns, and the current state of the repository.
*   **Recommendations:** When suggesting code changes, provide them as tool calls or code blocks for review rather than committing them automatically.
