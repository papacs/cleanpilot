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

    def test_app_uses_pyinstaller_resource_root(self):
        source = Path("src/cleanpilot_qt/app.py").read_text(encoding="utf-8")

        self.assertIn("_MEIPASS", source)


if __name__ == "__main__":
    unittest.main()
