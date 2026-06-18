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


if __name__ == "__main__":
    unittest.main()
