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


if __name__ == "__main__":
    unittest.main()
