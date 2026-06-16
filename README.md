# CleanPilot

CleanPilot is a safe Windows 10/11 disk cleanup assistant.

It scans first, reports what can be cleaned, and only removes files from explicit allowlisted cache and maintenance locations. The current release is script-first, with a planned .NET 8 WPF desktop app for progress, selectable cleanup categories, and a polished Windows utility experience.

## Safety Model

CleanPilot is conservative by default:

- Dry-run scanning is supported before deletion.
- Cleanup targets are explicit allowlists.
- Personal libraries are excluded.
- Program installation folders are excluded.
- Driver store cleanup is excluded.
- Restore point deletion is excluded.
- `DISM /ResetBase` is excluded.
- Locked files are skipped instead of forcing deletion.

The project does not bundle WizTree or other proprietary disk analyzers. If you want to use WizTree as a visual companion, download it yourself and pass `-WizTreePath`.

## Quick Start

Preview cleanup candidates without deleting files:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\SafeDiskCleanup.ps1 -DryRun
```

Preview deeper developer and upgrade-residue cleanup:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\SafeDiskCleanup.ps1 -DryRun -Aggressive -MinAgeDays 14
```

Run conservative cleanup:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\SafeDiskCleanup.ps1
```

Run as Administrator using the launcher:

```text
Run-SafeDiskCleanup-AsAdmin.cmd
```

## Current Features

- User and Windows temporary file cleanup.
- Windows Update download cache cleanup.
- Delivery Optimization cache cleanup.
- Windows Error Reporting cache cleanup.
- CBS and DISM archived log cleanup.
- Chrome, Edge, and Firefox cache cleanup.
- Optional developer cache cleanup in aggressive mode.
- Optional Windows upgrade residue cleanup in aggressive mode.
- Optional DISM component cleanup with `-IncludeDism`.
- Log file generation.
- Lightweight validation tests.

## Roadmap

- JSON Lines engine output for UI integration.
- Stable cleanup target IDs and selected-target cleaning.
- .NET 8 WPF desktop app.
- Progress bar, event log, risk labels, and final cleanup report.
- Self-contained Windows x64 release package.

## Test

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-SafeDiskCleanup.ps1
```

## License

MIT. See [LICENSE](LICENSE).
