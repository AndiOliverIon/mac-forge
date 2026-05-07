# Kendo Suite License Setup

This note records the repeatable setup steps only. Do not commit Telerik/Kendo
license keys, token values, or downloaded license files to this repository.

## What the local setup uses

Kendo/Telerik licensing is provided by a user-level license file:

- macOS/Linux: `~/.telerik/telerik-license.txt`
- Windows: `%AppData%\Telerik\telerik-license.txt`

Kendo also accepts the older `kendo-ui-license.txt` name and the
`TELERIK_LICENSE` or `KENDO_UI_LICENSE` environment variables, but the
user-level `telerik-license.txt` file is the preferred local development setup.

## macOS Setup

From a project that uses Kendo UI:

```sh
npm install --save @progress/kendo-licensing
npx kendo-ui-license refresh
npx kendo-ui-license activate
npx kendo-ui-license info
```

The `refresh` command opens the Telerik login flow and writes the license file
under `~/.telerik/`.

## Cerber / Windows Setup

Use `cmd.exe`, or call `.cmd` explicitly from PowerShell because PowerShell may
block `npm.ps1`/`npx.ps1` scripts.

From the Perform Angular client:

```bat
cd /d C:\work\ardis-perform\ardis.perform.client
npx.cmd kendo-ui-license refresh
npx.cmd kendo-ui-license activate
npx.cmd kendo-ui-license info
```

Expected license file location:

```text
C:\Users\oliver\AppData\Roaming\Telerik\telerik-license.txt
```

## If `kendo-ui-license` Is Missing

Install the licensing package in the project first:

```bat
npm.cmd install --save @progress/kendo-licensing
```

Then run the refresh, activate, and info commands again.

## Verification

The info command should report:

- The license file was found.
- Kendo UI for Angular is licensed for the current project.
- The covered products and expiration date match the active Telerik account.

## Security Notes

- Do not add `telerik-license.txt` or `kendo-ui-license.txt` to this repository.
- Do not store `TELERIK_LICENSE` or `KENDO_UI_LICENSE` values in markdown,
  scripts, shell history snippets, or git-tracked config.
- For local Windows development, prefer the license file over environment
  variables because large license values can be truncated.
