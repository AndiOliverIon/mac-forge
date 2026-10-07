# PERFORM Local License Chapter Bypass

## Purpose

Use this note when a new PERFORM license chapter must work locally before the real Efficy license
contains it. The `p` and `pr` aliases already own this lifecycle; do not rediscover or redesign the
flow for each chapter.

## Command Surface

- `p` runs `~/mac-forge/scripts/patch.sh` and applies the local PERFORM overrides.
- `pr` runs `patch -R`, removes those overrides, and restores the original chapter restriction list.
- `p --custom` opens the local chapter editor so individual module amounts can be changed.

The macOS aliases are in `~/mac-forge/dotfiles/aliases`. Linux has matching aliases in
`~/mac-forge/linux/aliases.zsh`. A new chapter normally requires no alias change.

## Files And Responsibilities

- `~/mac-forge/scripts/patch.sh`
  - On `p`, snapshots the original chapter restriction list before applying code overrides.
  - On `pr`, removes the overrides and restores the original list.
- `~/mac-forge/scripts/license-chapters.sh`
  - Resolves the active PERFORM repository and its configured `Ardis:ExternalFolder`.
  - Manages `wwwroot/license/offline/currentModuleRestrictionList.json` and
    `currentModuleRestrictionList.original.json` under the active license root.
  - Builds the `p --custom` chapter list from shared license constants, existing JSON records, and
    `EnsureModule(...)` calls in the local mock.
  - Recognizes both `EnsureModule(CLI.SomeModule, 1)` and
    `EnsureModule("SomeModule", 1)`.
- `<perform-repo>/local-overrides/MockLicenseService.cs`
  - This ignored, station-local file is the bypass implementation activated by `p`.
  - Its `AmountModule` result comes from the working restriction list plus modules added through
    `EnsureModule`.
  - It is intentionally not committed to the PERFORM repository.

## Adding A New Desired Chapter

1. Resolve the current PERFORM repository and read its applicable instructions. The usual Hades
   path is `/Users/oliver/work/ardis-perform`, but do not assume that path on another station.
2. Confirm the chapter's exact Efficy identifier, including casing and underscores.
3. Open `<perform-repo>/local-overrides/MockLicenseService.cs` and find the `finally` block in
   `loadModuleRestrictions()` immediately after `_mods ??= [];`.
4. Add a baseline module entry with amount `1`:

   ```csharp
   EnsureModule("PERF_New_Chapter", 1);
   ```

   Use the string form when the shared `CLI` constant has not landed yet. This lets the bypass
   compile before the product implementation exists. The string may remain after the constant is
   introduced, or be changed to `CLI.PERF_New_Chapter` later.
5. Do not add the chapter to `currentModuleRestrictionList.original.json`. That file is the state
   `pr` must restore. `EnsureModule` adds the temporary chapter only while the mock is active.
6. Verify that `scripts/license-chapters.sh` still recognizes the new `EnsureModule` call so
   `p --custom` shows the chapter with its forced baseline amount.
7. Run non-test checks:
   - `bash -n ~/mac-forge/scripts/license-chapters.sh ~/mac-forge/scripts/patch.sh`
   - Parse the local mock with the same `EnsureModule` pattern and confirm the chapter resolves to
     amount `1`.
8. Do not run `p`, restart PERFORM, run builds, or run unit tests unless Oliver requested that action.
   Preparing the bypass and activating it are separate operations.

## Runtime Lifecycle

When `p` is run:

1. The current chapter restriction list is saved as the original if no original snapshot exists.
2. Local override blocks are applied to the PERFORM checkout.
3. On the next PERFORM start, `MockLicenseService` reads the working restriction list.
4. `EnsureModule` inserts the desired chapter only when it is absent, preserving an explicit amount
   already present in the working list.

When `pr` is run:

1. The injected code blocks are removed.
2. The original chapter restriction list is copied back over the working list.
3. The local mock source remains on disk but is inactive.

Restart PERFORM after applying, removing, or editing the bypass so the active license service reloads
the chapter list.

## Verification And Troubleshooting

- Use `~/mac-forge/scripts/patch.sh status` from the PERFORM repository to see whether the overrides
  are applied, pending, or partially applied. This command is read-only.
- If the editor targets an unexpected JSON file, inspect `Ardis:ExternalFolder` in the active
  PERFORM configuration. The script intentionally prefers the external license folder over the
  in-repository fallback.
- If the chapter appears in `p --custom` but is denied at runtime, confirm that the override is
  applied and PERFORM was restarted.
- If `pr` unexpectedly preserves a temporary chapter, check whether it was written into the original
  snapshot. Restore the genuine baseline rather than teaching `pr` to special-case the chapter.
- Never print or copy Forge secret-store contents while diagnosing this flow.

## Current Example

For PER-6936, the local mock contains:

```csharp
EnsureModule("PERF_Script_Dialog", 1);
```

Mac Forge's chapter parser supports this literal form, so the bypass works before
`CLI.PERF_Script_Dialog` is added to the product code.
