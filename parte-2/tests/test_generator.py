from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from datetime import date
from pathlib import Path

MODULE_PATH = Path(__file__).parents[1] / "scripts" / "generate_raw.py"
SPEC = importlib.util.spec_from_file_location("generate_raw", MODULE_PATH)
assert SPEC and SPEC.loader
generate_raw = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = generate_raw
SPEC.loader.exec_module(generate_raw)


class GeneratorTests(unittest.TestCase):
    def test_same_seed_produces_same_summary_and_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            first = root / "first"
            second = root / "second"
            args = (date(2026, 9, 1), 3, 40, 42)
            summary_a = generate_raw.generate(first, *args)
            summary_b = generate_raw.generate(second, *args)
            self.assertEqual(summary_a, summary_b)
            files_a = sorted((first / "raw").rglob("*.ndjson"))
            files_b = sorted((second / "raw").rglob("*.ndjson"))
            self.assertEqual(
                [path.relative_to(first) for path in files_a],
                [path.relative_to(second) for path in files_b],
            )
            self.assertEqual(
                [path.read_bytes() for path in files_a],
                [path.read_bytes() for path in files_b],
            )

    def test_volume_quality_and_summary_are_consistent(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / "dataset"
            summary = generate_raw.generate(output, date(2026, 9, 1), 4, 150, 99)
            self.assertEqual(summary["base_orders"], 600)
            self.assertGreater(summary["base_items"], summary["base_orders"])
            self.assertGreater(summary["raw_events"], summary["base_items"])
            self.assertGreater(summary["duplicate_events"], 0)
            self.assertGreater(summary["invalid_events"], 0)
            self.assertGreater(summary["normalizable_events"], 0)
            self.assertEqual(
                summary["expected_valid_events_before_dedup"]
                - summary["expected_duplicates_removed"],
                summary["expected_trusted_rows"],
            )
            saved = json.loads((output / "generation-summary.json").read_text())
            self.assertEqual(saved, summary)

    def test_refuses_broad_output_directory(self) -> None:
        with self.assertRaises(ValueError):
            generate_raw.generate(Path("/"), date(2026, 9, 1), 1, 1, 1)

    def test_refuses_nonempty_unmarked_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / "existing"
            output.mkdir()
            (output / "user-file.txt").write_text("preserve me")
            with self.assertRaises(ValueError):
                generate_raw.generate(output, date(2026, 9, 1), 1, 1, 1)
            self.assertEqual((output / "user-file.txt").read_text(), "preserve me")


if __name__ == "__main__":
    unittest.main()

