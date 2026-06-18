# CleanPilot Qt Desktop App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a professional PySide6 Qt desktop app for CleanPilot without changing the existing PowerShell CLI behavior.

**Architecture:** Keep `SafeDiskCleanup.ps1` as the only cleanup engine. Add a thin Qt shell that calls the script through a tested Python engine adapter, parses dry-run output into UI rows, shows recommendations, progress, and logs, and packages dependencies with PyInstaller.

**Tech Stack:** Python 3.10, PySide6, PyInstaller, PowerShell 5.1+, stdlib `unittest`.

---

## File Structure

- Create: `src/cleanpilot_qt/__init__.py` - package marker.
- Create: `src/cleanpilot_qt/models.py` - dataclasses for cleanup candidates and run results.
- Create: `src/cleanpilot_qt/engine.py` - PowerShell command construction, dry-run parsing, recommendation logic, and subprocess runner.
- Create: `src/cleanpilot_qt/main_window.py` - PySide6 UI with toolbar buttons, table, recommendation panel, progress bar, and log view.
- Create: `src/cleanpilot_qt/app.py` - application entry point.
- Create: `src/cleanpilot_qt/resources/app.qss` - professional Windows utility styling.
- Create: `tests/test_qt_engine.py` - Python unit tests for engine behavior.
- Create: `tests/test_qt_ui_contract.py` - static UI contract tests for required widgets and labels.
- Create: `scripts/download_qt_wheels.ps1` - downloads fixed dependency wheels into `tools/wheels`.
- Create: `scripts/build_qt_app.ps1` - builds a self-contained PyInstaller release directory.
- Modify: `.gitignore` - ignore venv, wheel cache, PyInstaller outputs, and spec files.
- Modify: `README.md` - document Qt desktop usage and packaging commands.

## Task 1: Engine Adapter Model and Parser

**Files:**
- Create: `tests/test_qt_engine.py`
- Create: `src/cleanpilot_qt/__init__.py`
- Create: `src/cleanpilot_qt/models.py`
- Create: `src/cleanpilot_qt/engine.py`

- [x] **Step 1: Write failing parser and command tests**

Create `tests/test_qt_engine.py`:

```python
import unittest
from pathlib import Path

from src.cleanpilot_qt.engine import (
    build_powershell_command,
    parse_dry_run_line,
    recommendation_for_candidates,
)


class EngineAdapterTests(unittest.TestCase):
    def test_build_scan_command_keeps_cli_entrypoint(self):
        command = build_powershell_command(
            script_path=Path("SafeDiskCleanup.ps1"),
            dry_run=True,
            aggressive=False,
            min_age_days=30,
        )

        self.assertIn("-File", command)
        self.assertIn("SafeDiskCleanup.ps1", command)
        self.assertIn("-DryRun", command)
        self.assertIn("-MinAgeDays", command)
        self.assertIn("30", command)
        self.assertNotIn("-Aggressive", command)

    def test_build_deep_scan_command_adds_aggressive(self):
        command = build_powershell_command(
            script_path=Path("SafeDiskCleanup.ps1"),
            dry_run=True,
            aggressive=True,
            min_age_days=14,
        )

        self.assertIn("-Aggressive", command)
        self.assertIn("14", command)

    def test_parse_dry_run_line_extracts_candidate(self):
        line = (
            "2026-06-18 10:18:25 [INFO] DRY RUN: Chrome profile Default Cache "
            "would remove 3 files, estimated 256.36 KB, from "
            "C:\\Users\\dell\\AppData\\Local\\Google\\Chrome\\User Data\\Default\\Cache"
        )

        candidate = parse_dry_run_line(line)

        self.assertIsNotNone(candidate)
        self.assertEqual(candidate.name, "Chrome profile Default Cache")
        self.assertEqual(candidate.file_count, 3)
        self.assertEqual(candidate.estimated_size, "256.36 KB")
        self.assertEqual(candidate.risk, "安全")
        self.assertTrue(candidate.selected)

    def test_recommendation_mentions_admin_when_required_items_exist(self):
        line = (
            "2026-06-18 10:18:25 [WARN] Skip Windows Update download cache: "
            "Administrator rights required."
        )

        message = recommendation_for_candidates([], [line], is_admin=False)

        self.assertIn("管理员", message)
```

- [x] **Step 2: Run tests to verify they fail**

Run:

```powershell
python -m unittest tests.test_qt_engine -v
```

Expected: FAIL with `ModuleNotFoundError` because `src.cleanpilot_qt.engine` does not exist.

- [x] **Step 3: Add minimal models and engine adapter**

Create `src/cleanpilot_qt/__init__.py` as an empty file.

Create `src/cleanpilot_qt/models.py`:

```python
from dataclasses import dataclass


@dataclass
class CleanupCandidate:
    name: str
    path: str
    risk: str
    estimated_size: str
    file_count: int
    requires_admin: bool = False
    selected: bool = True
    status: str = "待处理"
    recommendation: str = ""
```

Create `src/cleanpilot_qt/engine.py`:

```python
import re
import subprocess
from pathlib import Path
from typing import Callable, Iterable

from .models import CleanupCandidate


DRY_RUN_PATTERN = re.compile(
    r"DRY RUN:\s+(?P<name>.+?)\s+would remove\s+(?P<count>\d+)\s+files,\s+"
    r"estimated\s+(?P<size>.+?),\s+from\s+(?P<path>.+)$"
)


def build_powershell_command(
    script_path: Path,
    dry_run: bool,
    aggressive: bool,
    min_age_days: int,
) -> list[str]:
    command = [
        "powershell",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(script_path),
        "-MinAgeDays",
        str(min_age_days),
    ]
    if dry_run:
        command.append("-DryRun")
    if aggressive:
        command.append("-Aggressive")
    return command


def classify_risk(name: str, path: str) -> str:
    text = f"{name} {path}".lower()
    if "windows.old" in text or "$windows.~bt" in text:
        return "需复核"
    if "npm" in text or "yarn" in text or "pip" in text or "nuget" in text:
        return "开发缓存"
    if "windows" in text or "dism" in text or "cbs" in text:
        return "系统维护"
    return "安全"


def parse_dry_run_line(line: str) -> CleanupCandidate | None:
    match = DRY_RUN_PATTERN.search(line)
    if not match:
        return None

    name = match.group("name").strip()
    path = match.group("path").strip()
    risk = classify_risk(name, path)
    selected = risk == "安全"
    recommendation = "建议清理" if selected else "建议先复核"
    return CleanupCandidate(
        name=name,
        path=path,
        risk=risk,
        estimated_size=match.group("size").strip(),
        file_count=int(match.group("count")),
        selected=selected,
        recommendation=recommendation,
    )


def recommendation_for_candidates(
    candidates: Iterable[CleanupCandidate],
    log_lines: Iterable[str],
    is_admin: bool,
) -> str:
    lines = list(log_lines)
    items = list(candidates)
    if not is_admin and any("Administrator rights required" in line for line in lines):
        return "建议以管理员身份重新扫描，以便发现和清理系统缓存。"
    if not items:
        return "当前没有发现可清理项，可稍后再扫描。"
    safe_count = sum(1 for item in items if item.risk == "安全")
    review_count = len(items) - safe_count
    if review_count:
        return f"建议先清理 {safe_count} 个安全项；{review_count} 个项目需要复核路径后再处理。"
    return f"建议清理 {safe_count} 个安全项。"


def run_command(
    command: list[str],
    cwd: Path,
    on_line: Callable[[str], None],
) -> int:
    process = subprocess.Popen(
        command,
        cwd=str(cwd),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    assert process.stdout is not None
    for line in process.stdout:
        on_line(line.rstrip())
    return process.wait()
```

- [x] **Step 4: Run tests to verify they pass**

Run:

```powershell
python -m unittest tests.test_qt_engine -v
```

Expected: PASS.

- [x] **Step 5: Commit**

Run:

```powershell
git add src/cleanpilot_qt/__init__.py src/cleanpilot_qt/models.py src/cleanpilot_qt/engine.py tests/test_qt_engine.py
git commit -m "feat: add Qt engine adapter"
```

## Task 2: Qt UI Contract and Main Window

**Files:**
- Create: `tests/test_qt_ui_contract.py`
- Create: `src/cleanpilot_qt/main_window.py`
- Create: `src/cleanpilot_qt/app.py`
- Create: `src/cleanpilot_qt/resources/app.qss`

- [x] **Step 1: Write failing UI contract test**

Create `tests/test_qt_ui_contract.py`:

```python
import unittest
from pathlib import Path


class QtUiContractTests(unittest.TestCase):
    def test_main_window_contains_required_professional_controls(self):
        source = Path("src/cleanpilot_qt/main_window.py").read_text(encoding="utf-8")

        for required in [
            "QProgressBar",
            "QTableWidget",
            "QTextEdit",
            "recommendation_label",
            "scan_button",
            "clean_button",
            "open_log_button",
            "安全模式",
            "深度扫描",
        ]:
            self.assertIn(required, source)

    def test_stylesheet_uses_status_and_recommendation_styles(self):
        source = Path("src/cleanpilot_qt/resources/app.qss").read_text(encoding="utf-8")

        for required in ["QProgressBar", "QTableWidget", "#recommendationPanel", "#primaryButton"]:
            self.assertIn(required, source)
```

- [x] **Step 2: Run UI contract test to verify it fails**

Run:

```powershell
python -m unittest tests.test_qt_ui_contract -v
```

Expected: FAIL because `main_window.py` and `app.qss` do not exist.

- [x] **Step 3: Create Qt main window**

Create `src/cleanpilot_qt/main_window.py` with a `CleanPilotWindow` class that:

- Builds a `QMainWindow`.
- Adds `scan_button`, `clean_button`, `open_log_button`, and `open_script_button`.
- Adds mode radio buttons for `安全模式` and `深度扫描`.
- Adds a `QTableWidget` with candidate columns.
- Adds `recommendation_label`.
- Adds a `QProgressBar`.
- Adds a read-only `QTextEdit` for logs.
- Uses `QThread` to run the engine without blocking the UI.
- Updates progress as log lines arrive.
- Opens the log directory with `os.startfile`.

The implementation must keep all cleanup execution routed through `SafeDiskCleanup.ps1`.

- [x] **Step 4: Create Qt app entry point**

Create `src/cleanpilot_qt/app.py`:

```python
import sys
from pathlib import Path

from PySide6.QtWidgets import QApplication

from .main_window import CleanPilotWindow


def main() -> int:
    app = QApplication(sys.argv)
    qss_path = Path(__file__).parent / "resources" / "app.qss"
    if qss_path.exists():
        app.setStyleSheet(qss_path.read_text(encoding="utf-8"))

    window = CleanPilotWindow(repo_root=Path(__file__).resolve().parents[2])
    window.resize(1180, 760)
    window.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
```

- [x] **Step 5: Create professional stylesheet**

Create `src/cleanpilot_qt/resources/app.qss` with:

```css
QMainWindow {
    background: #f6f8fb;
    color: #172033;
    font-family: "Microsoft YaHei UI", "Segoe UI";
    font-size: 13px;
}

QPushButton {
    border: 1px solid #c8d1df;
    background: #ffffff;
    padding: 8px 12px;
    border-radius: 6px;
}

QPushButton#primaryButton {
    background: #1769e0;
    color: white;
    border-color: #1769e0;
    font-weight: 600;
}

QLabel#recommendationPanel {
    background: #eef6ff;
    border: 1px solid #b9d7ff;
    border-radius: 6px;
    padding: 10px;
    color: #174a8b;
}

QTableWidget {
    background: #ffffff;
    border: 1px solid #d8dee9;
    gridline-color: #edf1f7;
    selection-background-color: #dcecff;
}

QProgressBar {
    border: 1px solid #c8d1df;
    border-radius: 5px;
    height: 14px;
    text-align: center;
    background: #ffffff;
}

QProgressBar::chunk {
    background: #1b7f4c;
    border-radius: 5px;
}

QTextEdit {
    background: #101828;
    color: #e6edf7;
    border: 1px solid #25344f;
    border-radius: 6px;
    font-family: "Cascadia Mono", Consolas;
    font-size: 12px;
}
```

- [x] **Step 6: Run UI contract test to verify it passes**

Run:

```powershell
python -m unittest tests.test_qt_ui_contract -v
```

Expected: PASS.

- [x] **Step 7: Commit**

Run:

```powershell
git add src/cleanpilot_qt/main_window.py src/cleanpilot_qt/app.py src/cleanpilot_qt/resources/app.qss tests/test_qt_ui_contract.py
git commit -m "feat: add Qt desktop interface"
```

## Task 3: Dependency Download and Build Scripts

**Files:**
- Create: `scripts/download_qt_wheels.ps1`
- Create: `scripts/build_qt_app.ps1`
- Modify: `.gitignore`

- [x] **Step 1: Write failing static script checks**

Extend `tests/test_qt_ui_contract.py` with:

```python
    def test_packaging_scripts_cache_dependencies_and_build_release(self):
        download_script = Path("scripts/download_qt_wheels.ps1").read_text(encoding="utf-8")
        build_script = Path("scripts/build_qt_app.ps1").read_text(encoding="utf-8")

        self.assertIn("tools\\wheels", download_script)
        self.assertIn("PySide6", download_script)
        self.assertIn("PyInstaller", download_script)
        self.assertIn("--no-index", build_script)
        self.assertIn("--find-links", build_script)
        self.assertIn("CleanPilot.exe", build_script)
        self.assertIn("SafeDiskCleanup.ps1", build_script)
```

- [x] **Step 2: Run static script checks to verify they fail**

Run:

```powershell
python -m unittest tests.test_qt_ui_contract -v
```

Expected: FAIL because build scripts do not exist.

- [x] **Step 3: Create dependency download script**

Create `scripts/download_qt_wheels.ps1` that:

- Requires Python 3.10+.
- Creates `tools\wheels`.
- Downloads fixed versions of `PySide6`, `shiboken6`, and `PyInstaller` with `python -m pip download`.

- [x] **Step 4: Create build script**

Create `scripts/build_qt_app.ps1` that:

- Creates `.venv-qt`.
- Installs from `tools\wheels` using `--no-index --find-links`.
- Runs PyInstaller with app name `CleanPilot`.
- Adds `SafeDiskCleanup.ps1` and `Run-SafeDiskCleanup-AsAdmin.cmd` into the release directory.
- Verifies `dist\CleanPilot\CleanPilot.exe` exists.

- [x] **Step 5: Update `.gitignore`**

Add:

```gitignore
.venv-qt/
build/
dist/
*.spec
tools/wheels/
```

- [x] **Step 6: Run static script checks to verify they pass**

Run:

```powershell
python -m unittest tests.test_qt_ui_contract -v
```

Expected: PASS.

- [x] **Step 7: Commit**

Run:

```powershell
git add scripts/download_qt_wheels.ps1 scripts/build_qt_app.ps1 .gitignore tests/test_qt_ui_contract.py
git commit -m "build: add Qt desktop packaging scripts"
```

## Task 4: README Documentation

**Files:**
- Modify: `README.md`

- [x] **Step 1: Add desktop usage documentation**

Add Chinese sections that describe:

- Qt desktop app capabilities: progress bar, recommendation panel, log viewer, scan and clean buttons.
- How to run from source after installing dependencies.
- How to download dependency wheels.
- How to build a self-contained Windows release.
- Confirmation that existing CLI commands still work.

- [x] **Step 2: Run documentation and CLI verification**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-SafeDiskCleanup.ps1
python -m unittest tests.test_qt_engine tests.test_qt_ui_contract -v
```

Expected: both commands PASS.

- [x] **Step 3: Commit**

Run:

```powershell
git add README.md
git commit -m "docs: document Qt desktop app"
```

## Task 5: Local Dependency Install, Smoke Run, and Build Verification

**Files:**
- Use: `scripts/download_qt_wheels.ps1`
- Use: `scripts/build_qt_app.ps1`
- Use: `src/cleanpilot_qt/app.py`

- [ ] **Step 1: Download dependency wheels**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\download_qt_wheels.ps1
```

Expected: `tools\wheels` contains PySide6, shiboken6, and PyInstaller wheels.

- [ ] **Step 2: Build release directory**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_qt_app.ps1
```

Expected: `dist\CleanPilot\CleanPilot.exe` exists.

- [ ] **Step 3: Run final tests**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-SafeDiskCleanup.ps1
python -m unittest tests.test_qt_engine tests.test_qt_ui_contract -v
```

Expected: both commands PASS.

- [ ] **Step 4: Final safety check**

Run:

```powershell
rg -n "ResetBase|vssadmin|Delete\s+Shadows|pnputil|DriverStore|Register-ScheduledTask|Unregister-ScheduledTask|New-ScheduledTask" SafeDiskCleanup.ps1 src scripts tests
```

Expected: no unsafe matches in cleanup behavior.

- [ ] **Step 5: Commit verification updates if needed**

If build verification required script or documentation fixes, commit them with:

```powershell
git add .
git commit -m "chore: verify Qt desktop release build"
```
