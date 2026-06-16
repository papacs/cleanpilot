# Safe Disk Cleanup Design

## Goal

Build a Win10/Win11 PowerShell cleanup script that can be run manually to reclaim C drive space safely and quickly.

## Selected Approach

Use a single professional PowerShell script with conservative defaults and opt-in aggressive cleanup. The script favors Windows-supported cleanup mechanisms and explicit whitelisted cache paths over broad deletion.

## Default Behavior

- Requires no configuration for normal use.
- Elevates effectiveness when run as Administrator, while still supporting limited non-admin cleanup.
- Supports `-DryRun` for reporting candidates without deletion.
- Supports optional `-OpenWizTree` inspection when WizTree Portable is placed next to the script under `tools\WizTree\WizTree64.exe`.
- Uses `-MinAgeDays 7` by default so recent cache files are not removed.
- Logs all actions, reclaimed sizes, skipped files, and errors.
- Cleans user and system temporary files, Windows Update download cache, Delivery Optimization cache, Windows Error Reporting cache, old CBS/DISM log archives, browser caches, and the recycle bin.
- Skips Windows component store cleanup by default; runs `DISM /Online /Cleanup-Image /StartComponentCleanup` only when `-IncludeDism` is explicitly passed.
- Includes a double-click launcher that asks for Administrator rights and leaves the PowerShell window open after completion.

## Safety Boundaries

- Never targets personal libraries such as Downloads, Desktop, Documents, Pictures, Music, or Videos.
- Never targets application installation directories under Program Files.
- Never deletes driver store contents.
- Does not delete all restore points.
- Does not use `DISM /ResetBase` by default.
- Uses explicit path allowlists and existence checks before deletion.
- Handles locked files as skips rather than hard failures.
- Deletes directories only after verifying they are empty, and suppresses PowerShell's recursive-delete confirmation prompt explicitly.
- Treats DISM component cleanup as an optional Windows maintenance step because it can fail with system-level access or servicing-stack errors even after normal cleanup succeeds.

## Optional WizTree Companion

WizTree is not bundled or downloaded by this project. For internal use, place the portable executable at `tools\WizTree\WizTree64.exe` beside `SafeDiskCleanup.ps1`, or pass an explicit `-WizTreePath`. When `-OpenWizTree` is used, the script launches WizTree against `-ScanPath` (default: the system drive) so a user can visually inspect large folders before deciding what to clean. The cleanup script never deletes files based on WizTree output; WizTree is an inspection aid, while scripted deletion remains limited to the safe target allowlist.

## Optional Aggressive Behavior

The `-Aggressive` switch may include older Windows upgrade residue such as `Windows.old` and `$WINDOWS.~BT` when present, plus deeper browser and package-manager cache cleanup. It still avoids personal data and rollback-hostile actions such as deleting all restore points.

## Optional DISM Behavior

The `-IncludeDism` switch runs Windows component store cleanup through DISM. This is useful when the system servicing stack allows it, but it is not part of the default internal cleanup path because DISM may return access or CBS servicing errors that do not affect normal cache cleanup.

## Deliverables

- `SafeDiskCleanup.ps1`: user-facing cleanup script.
- `Run-SafeDiskCleanup-AsAdmin.cmd`: double-click launcher for manual cleanup.
- `tests/Test-SafeDiskCleanup.ps1`: lightweight validation tests.
- Optional internal folder: `tools\WizTree\WizTree64.exe` supplied by the user or organization, not stored in this repository.

## Verification

- Parse the script with PowerShell to catch syntax errors.
- Run tests that assert parameters, safety exclusions, dry-run support, scheduling support, DISM behavior, and absence of unsafe defaults.
- Run tests that verify empty-directory cleanup does not attempt to delete non-empty directories.
- Run a dry-run invocation to verify it reports without deleting.

## Notes

This workspace is not a git repository, so the design document cannot be committed here.
