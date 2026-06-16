# Open Source WPF Desktop Redesign

## Goal

Turn SafeDiskCleanup from a script-first Windows cleanup utility into a trustworthy open source Windows 10/11 desktop tool with a polished WPF interface, visible progress, auditable cleanup details, and clean release packaging.

## Product Positioning

SafeDiskCleanup should be positioned as a safe Windows C drive cleanup assistant for developers and power users:

- Scan first, clean second.
- Show every cleanup category before deletion.
- Use explicit allowlists instead of broad folder deletion.
- Avoid personal files, driver stores, restore point deletion, and bundled proprietary analyzers.
- Keep the PowerShell engine usable for automation while making the desktop app the primary user experience.

## Selected Approach

Use `.NET 8 + WPF` for the Windows desktop client and keep PowerShell as the cleanup engine.

The desktop app launches the PowerShell engine as an elevated child process when cleanup requires Administrator rights. The engine emits structured JSON Lines events in addition to plain text logs, so the UI can render progress, category tables, warnings, and final summaries without parsing free-form text.

This is preferred over Electron, Tauri, or WinUI 3 because WPF is smaller, more native to Windows administration tools, mature, easy to package as a self-contained app, and well suited for process control and system utility interfaces.

## Non-Goals For First Desktop Release

- No browser-based UI.
- No cross-platform support.
- No background scheduled cleanup.
- No automatic cleanup on startup.
- No bundled WizTree binary or other proprietary analyzer.
- No deletion outside explicit allowlisted cleanup targets.
- No registry cleaning, driver store cleaning, or restore point deletion.

## Repository Restructure

Recommended structure:

```text
SafeDiskCleanup.ps1
Run-SafeDiskCleanup-AsAdmin.cmd
src/
  SafeDiskCleanup.App/
    SafeDiskCleanup.App.csproj
    App.xaml
    MainWindow.xaml
    MainWindow.xaml.cs
    Models/
    Services/
    ViewModels/
tests/
  Test-SafeDiskCleanup.ps1
docs/
  screenshots/
  superpowers/
.github/
  workflows/
README.md
LICENSE
CHANGELOG.md
SECURITY.md
.gitignore
```

The existing `tools/WizTree` folder should be removed from the public repository. The script may still support `-WizTreePath`, but documentation must require users to download WizTree themselves if they want that companion workflow.

## Desktop User Experience

The first screen is the actual cleanup workspace, not a marketing page.

Top area:

- App name, current drive, used/free capacity, and Administrator status.
- Primary actions: `Scan`, `Clean Selected`, `Open Log`, `Settings`.
- Mode selector: `Safe` and `Deep Scan`.

Main workspace:

- Cleanup category table with columns: category, path, risk level, eligible files, estimated size, selected state, and status.
- Risk labels: `Safe`, `Developer Cache`, `Windows Maintenance`, `Review`.
- Details panel showing what a selected category contains and why it is safe or requires review.

Bottom area:

- Overall progress bar.
- Current operation text.
- Event log stream with warnings highlighted.
- Final summary with reclaimed size, skipped files, and log path.

The visual style should be professional and utilitarian: dense but readable tables, restrained colors, clear status badges, native Windows spacing, and no decorative hero layout.

## Cleanup Flow

1. User opens the app.
2. App checks whether it is running elevated.
3. User clicks `Scan`.
4. App runs the engine in dry-run mode with JSONL output enabled.
5. Engine reports each cleanup target with estimated reclaimable size and risk metadata.
6. UI displays candidates and lets the user select allowed targets.
7. User clicks `Clean Selected`.
8. If elevated rights are needed and missing, app relaunches itself or the engine with Administrator rights.
9. Engine cleans selected targets and streams progress events.
10. UI updates progress, logs warnings, and shows a final summary.

## Engine Contract

`SafeDiskCleanup.ps1` should gain machine-readable output without breaking current command-line usage.

New parameters:

- `-JsonLines`: emit one JSON object per line for UI consumption.
- `-IncludeTargets <string[]>`: clean only named target IDs selected by the UI.
- `-NoRecycleBin`: allow the UI to treat recycle bin cleanup as an explicit selectable item.

Each cleanup target should have a stable ID and metadata:

- `id`
- `name`
- `path`
- `risk`
- `requiresAdmin`
- `aggressiveOnly`
- `minimumAgeDays`
- `description`

Core event types:

- `started`
- `target_discovered`
- `target_estimated`
- `target_started`
- `file_removed`
- `target_completed`
- `warning`
- `error`
- `summary`

The UI must depend on these events, not free-form log strings.

## Open Source Readiness

Before public promotion:

- Remove bundled WizTree binaries and locale files.
- Add `.gitignore` entries for local tools, logs, build outputs, and temporary packages.
- Add `README.md` with screenshots, safety model, quick start, CLI usage, desktop usage, and examples.
- Add an open source license, preferably MIT unless there is a reason to choose a more restrictive license.
- Add `SECURITY.md` explaining how to report unsafe cleanup behavior.
- Add `CHANGELOG.md` starting at `0.1.0`.
- Add GitHub Actions for PowerShell parser validation, script tests, and .NET build.
- Add release packaging instructions for a self-contained Windows x64 build.

## Safety Rules

The existing safety posture remains mandatory:

- Never target Downloads, Desktop, Documents, Pictures, Music, or Videos.
- Never target `Program Files` installation folders.
- Never manually delete `WinSxS`, `Windows\Installer`, driver store contents, or restore points.
- Never use `DISM /ResetBase`.
- Never use `vssadmin delete shadows`.
- Treat locked files as skips.
- Prefer Windows-supported cleanup commands where available.
- Default to dry-run scan before cleanup.

The desktop app must expose these rules in concise user-facing copy, especially before `Clean Selected`.

## Testing Strategy

PowerShell tests:

- Parser validation.
- Parameter and function contract validation.
- Unsafe pattern checks.
- JSONL schema checks.
- Include-target filtering behavior.
- Dry-run does not delete files.

.NET tests:

- JSONL parser maps engine events to view models.
- Progress aggregation handles missing or warning events.
- Target selection produces the expected `-IncludeTargets` arguments.
- Admin detection and relaunch command construction are correct.

Manual verification:

- Run scan without Administrator rights.
- Run scan with Administrator rights.
- Run cleanup against a temporary fixture path.
- Verify progress and logs remain responsive during long scans.
- Verify final release build launches on Windows 10/11.

## Release Milestones

### Milestone 1: Trustworthy Open Source Baseline

Remove proprietary binaries, add README, license, security policy, changelog, gitignore, and CI for the current script.

### Milestone 2: Structured Engine

Add stable cleanup target IDs, JSONL events, target filtering, and tests while preserving existing CLI behavior.

### Milestone 3: WPF Desktop MVP

Create the .NET 8 WPF app with scan, selectable targets, progress bar, log stream, admin status, and clean selected flow.

### Milestone 4: Polished Release

Add screenshots, release packaging, signed or checksumed artifacts, improved docs, and a first public `0.1.0` release.

## Acceptance Criteria

- The repository can be published without bundled proprietary executables.
- A new user can understand what the tool will and will not delete from the README.
- The CLI still supports safe dry-run and cleanup.
- The WPF app can scan, show estimated cleanup categories, clean selected targets, display progress, and show a final report.
- Automated tests cover script safety contracts and the UI event parser.
- The project has enough trust material for GitHub promotion: license, CI, screenshots, security policy, changelog, and release notes.

## Notes

This workspace is not currently a git repository, so this design document cannot be committed here until a repository is initialized.
