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


@dataclass
class CleanupSummary:
    removed_files: int
    skipped_files: int
    reclaimed_size: str
