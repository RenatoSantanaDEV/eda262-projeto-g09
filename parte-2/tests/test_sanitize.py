from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).parents[1] / "scripts" / "sanitize.py"
SPEC = importlib.util.spec_from_file_location("sanitize", MODULE_PATH)
assert SPEC and SPEC.loader
sanitize = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = sanitize
SPEC.loader.exec_module(sanitize)


class SanitizerTests(unittest.TestCase):
    def test_redacts_account_and_aws_keys(self) -> None:
        fake_key = "AKIA" + "ABCDEFGHIJKLMNOP"
        secret_label = "aws_secret_" + "access_key"
        source = (
            "/Users/alguem/projeto contato@example.com "
            "arn:aws:iam::123456789012:role/demo "
            f"{fake_key} "
            f"{secret_label}=not-a-real-secret"
        )
        result = sanitize.sanitize(source)
        self.assertNotIn("123456789012", result)
        self.assertNotIn(fake_key, result)
        self.assertNotIn("not-a-real-secret", result)
        self.assertNotIn("/Users/alguem", result)
        self.assertNotIn("contato@example.com", result)
        self.assertIn("<ACCOUNT_ID>", result)


if __name__ == "__main__":
    unittest.main()

