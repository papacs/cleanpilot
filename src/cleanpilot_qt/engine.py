import re
import subprocess
from pathlib import Path
from typing import Callable, Iterable

from .models import CleanupCandidate, CleanupSummary


DRY_RUN_PATTERN = re.compile(
    r"DRY RUN:\s+(?P<name>.+?)\s+would remove\s+(?P<count>\d+)\s+files,\s+"
    r"estimated\s+(?P<size>.+?),\s+from\s+(?P<path>.+)$"
)

CLEANUP_SUMMARY_PATTERN = re.compile(
    r"Cleanup completed\.\s+Removed files=(?P<removed>\d+),\s+"
    r"skipped=(?P<skipped>\d+),\s+estimated reclaimed=(?P<reclaimed>.+)$"
)

SIZE_UNITS = {
    "B": 1,
    "KB": 1024,
    "MB": 1024**2,
    "GB": 1024**3,
    "TB": 1024**4,
}


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


def parse_size_to_bytes(size_text: str) -> int:
    parts = size_text.strip().split()
    if not parts:
        return 0
    try:
        value = float(parts[0].replace(",", ""))
    except ValueError:
        return 0
    unit = parts[1].upper() if len(parts) > 1 else "B"
    multiplier = SIZE_UNITS.get(unit, 1)
    return int(value * multiplier)


def parse_dry_run_line(line: str) -> CleanupCandidate | None:
    match = DRY_RUN_PATTERN.search(line)
    if not match:
        return None

    name = match.group("name").strip()
    path = match.group("path").strip()
    estimated_size = match.group("size").strip()
    if parse_size_to_bytes(estimated_size) <= 0:
        return None

    risk = classify_risk(name, path)
    selected = risk == "安全"
    recommendation = "建议清理" if selected else "建议先复核"
    return CleanupCandidate(
        name=name,
        path=path,
        risk=risk,
        estimated_size=estimated_size,
        file_count=int(match.group("count")),
        selected=selected,
        recommendation=recommendation,
    )


def parse_cleanup_summary(line: str) -> CleanupSummary | None:
    match = CLEANUP_SUMMARY_PATTERN.search(line)
    if not match:
        return None
    return CleanupSummary(
        removed_files=int(match.group("removed")),
        skipped_files=int(match.group("skipped")),
        reclaimed_size=match.group("reclaimed").strip(),
    )


def cleanup_followup_message(removed_files: int, skipped_files: int, reclaimed_size: str) -> str:
    if skipped_files > 0 and parse_size_to_bytes(reclaimed_size) <= 0:
        return f"清理完成，但 {skipped_files} 个文件被系统跳过，未实际释放空间。建议查看日志，或重启后重新扫描。"
    if skipped_files > 0:
        return f"清理完成，预计释放 {reclaimed_size}；另有 {skipped_files} 个文件被系统跳过。"
    return f"清理完成，预计释放 {reclaimed_size}。"


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
