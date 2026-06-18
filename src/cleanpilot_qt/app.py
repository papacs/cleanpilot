import sys
from pathlib import Path

from PySide6.QtWidgets import QApplication

from .main_window import CleanPilotWindow


def resolve_runtime_root() -> Path:
    if hasattr(sys, "_MEIPASS"):
        return Path(getattr(sys, "_MEIPASS"))
    return Path(__file__).resolve().parents[2]


def main() -> int:
    app = QApplication(sys.argv)
    runtime_root = resolve_runtime_root()
    qss_path = runtime_root / "src" / "cleanpilot_qt" / "resources" / "app.qss"
    if not qss_path.exists():
        qss_path = Path(__file__).parent / "resources" / "app.qss"
    if qss_path.exists():
        app.setStyleSheet(qss_path.read_text(encoding="utf-8"))

    window = CleanPilotWindow(repo_root=runtime_root)
    window.resize(1180, 760)
    window.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
