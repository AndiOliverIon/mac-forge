# Gemini Workspace Documentation

This document provides an overview of the `mac-forge` repository, its structure, and the purpose of its scripts and configuration files.

## Project Overview

`mac-forge` is a personal collection of scripts and configuration files designed to automate and streamline the user's development and system management workflow on macOS. The repository includes tools for managing Docker, databases, git branches, system settings, and organizing files.

## Directory Structure

- **`/configs`**: Contains JSON configuration files for various scripts.
  - `web.json`: A list of URLs for quick access, likely used by `scripts/web.sh`.
  - `work-state.json`: Defines paths for Docker, database snapshots, and rules for the file organizer script.
- **`/dotfiles`**: Contains shell configuration files.
  - `zshrc`: Configuration for the Zsh shell.
  - `p10k.zsh`: Configuration for the Powerlevel10k Zsh theme.
  - `aliases`: Custom shell aliases.
- **`/scripts`**: A collection of shell scripts for various tasks.
- **`/work`**: A directory for work-related files.

## Key Scripts

This is not an exhaustive list, but it covers some of the main functionalities provided by the scripts in the `scripts` directory.

### Workflow & Automation

- **`forge.sh`**: A master script that seems to be the main entry point for many operations.
- **`work.sh`**: A script to manage work-related tasks, possibly setting up a work environment.
- **`organizer.sh`**: Cleans up specified folders (like Downloads and Desktop) by moving files into categorized subdirectories based on rules in `configs/work-state.json`.
- **`info.sh`**: Displays system information.
- **`arc.sh`**: Likely related to Arcanist (a code review tool from Phabricator).

### Docker & Database Management

- **`docker-start.sh`**: Starts Docker containers.
- **`db-admin.sh`**: Opens a database administration tool.
- **`db-snapshot.sh`**: Creates a snapshot of a database.
- **`db-restore.sh`**: Restores a database from a snapshot.
- **`db-clear.sh`**: Clears a database.
- **`db-upload-bak.sh`**: Uploads a database backup file.

### Git & Branch Management

- **`branch-delete.sh`**: Deletes Git branches.
- **`branch-local-clean.sh`**: Cleans up local Git branches.
- **`git-del.sh`**: A script for deleting git-related things.

### System & Cleanup

- **`win-shortcut-clean.sh`**: Removes unwanted Windows application shortcuts created by Parallels.
- **`hdd-clean.sh`**: Cleans up a hard drive.
- **`eject-all.sh`**: Ejects all connected external drives.
- **`bin-clear.sh`**: Clears a `bin` directory.

## Configuration

The behavior of many scripts is controlled by the JSON files in the `/configs` directory.

- **`web.json`**: Add or remove URLs to be opened by the `web.sh` script.
- **`work-state.json`**:
  - `docker-locations`: Configure different locations for Docker files and snapshots. This is useful for switching between different machines or external drives.
  - `organize-categories`: Define file extensions and their corresponding folders for the `organizer.sh` script.
  - `organize-folders`: Specify which folders the `organizer.sh` script should process.

## User Preferences & Environment

The `Readme.md` file contains personal notes for setting up a new Mac, including preferences for the Dock, Git configuration, keyboard settings, and installation of tools like `pyenv` and FortiClient VPN. This provides valuable context for the user's environment.
