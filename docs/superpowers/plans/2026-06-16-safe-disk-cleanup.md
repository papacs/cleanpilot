# Safe Disk Cleanup and WizTree Companion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix interactive deletion confirmations and add optional WizTree companion launch support without bundling third-party binaries.

**Architecture:** Keep one self-contained PowerShell cleanup script with conservative deletion rules. Empty-directory cleanup will verify directories are empty before deletion and pass `-Confirm:$false` to suppress recursive-delete prompts. WizTree support will be optional: the script discovers `tools\WizTree\WizTree64.exe` beside the script, or accepts `-WizTreePath`, and only launches it for visual inspection.

**Tech Stack:** PowerShell 5.1+ compatible syntax, Windows built-in cmdlets, DISM, optional locally supplied WizTree Portable executable.

---

### Task 1: Confirmation Regression Tests

**Files:**
- Modify: `tests/Test-SafeDiskCleanup.ps1`
- Target under test: `SafeDiskCleanup.ps1`

- [ ] **Step 1: Write failing tests**

Add assertions that `Remove-EmptyDirectories` leaves stale non-empty directories alone without counting them as skipped delete failures, removes stale empty directories, and that directory `Remove-Item` calls include `-Confirm:$false`.

- [ ] **Step 2: Run test to verify it fails**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-SafeDiskCleanup.ps1`

Expected: FAIL because the current directory cleanup attempts to delete non-empty directories and does not pass `-Confirm:$false`.

### Task 2: Directory Cleanup Fix

**Files:**
- Modify: `SafeDiskCleanup.ps1`
- Test: `tests/Test-SafeDiskCleanup.ps1`

- [ ] **Step 1: Implement minimal fix**

Change `Remove-EmptyDirectories` so it checks for child items first, skips non-empty directories without incrementing skipped delete failures, and removes only empty directories with `-Confirm:$false`.

### Task 3: WizTree Optional Companion

**Files:**
- Modify: `SafeDiskCleanup.ps1`
- Modify: `tests/Test-SafeDiskCleanup.ps1`

- [ ] **Step 1: Write failing tests**

Assert top-level parameters include `OpenWizTree`, `WizTreePath`, and `ScanPath`; functions include `Resolve-WizTreeExecutable` and `Start-WizTreeScan`; script content references `tools\WizTree\WizTree64.exe` and `/admin=1`.

- [ ] **Step 2: Run test to verify it fails**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-SafeDiskCleanup.ps1`

Expected: FAIL because WizTree parameters and helpers do not exist yet.

- [ ] **Step 3: Implement minimal support**

Add optional WizTree path resolution and startup. If no executable exists, log the expected placement path and continue. If `-OpenWizTree` is used and the executable exists, call `Start-Process` with the scan path and `/admin=1` when running elevated.

### Task 4: Verification

**Files:**
- Use: `SafeDiskCleanup.ps1`
- Use: `tests/Test-SafeDiskCleanup.ps1`

- [ ] **Step 1: Run tests**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-SafeDiskCleanup.ps1`

Expected: PASS.

- [ ] **Step 2: Run dry-run**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\SafeDiskCleanup.ps1 -DryRun -MinAgeDays 30`

Expected: Script prints a dry-run summary and does not delete files.

- [ ] **Step 3: Check unsafe commands**

Search the script for broad deletion patterns, personal folders, scheduled task commands, `ResetBase`, shadow copy deletion, and driver store deletion.

Expected: No unsafe pattern is present.

## Self-Review

- The plan covers the confirmation fix, optional WizTree companion launch, validation tests, dry-run verification, and final safety review.
- No destructive command is run during tests.
- The plan uses explicit file paths and concrete verification commands.
- This workspace is not a git repository, so commit steps are intentionally omitted.
