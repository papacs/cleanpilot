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
