from __future__ import annotations

import importlib.util
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from test_lf_grants import captured, evaluate, grant, table_resource, database_resource, ACCOUNT
from test_sanitize import sanitize

SCRIPTS = Path(__file__).parents[1] / "scripts"


class FinalRegressionTests(unittest.TestCase):
    def test_sanitizer_preserves_hashes_and_run_ids(self):
        digest = "abcdef123456789012" + "a" * 46
        self.assertEqual(len(digest), 64)
        source = f'{digest} jr_{digest} 123456789012 arn:aws:iam::123456789012:role/demo'
        result = sanitize.sanitize(source)
        self.assertIn(digest, result)
        self.assertIn(f"jr_{digest}", result)
        self.assertEqual(result.count("<ACCOUNT_ID>"), 2)

    def test_compatibility_grants_cannot_bypass_project_checks(self):
        for principal in ("IAM_ALLOWED_PRINCIPALS", "IAMAllowedPrincipals"):
            for resource in (table_resource("trusted_orders"), database_resource()):
                status, checks = evaluate(captured() + [grant(principal, resource, ["ALL"])])
                self.assertEqual(status, 1)
                self.assertEqual(checks["compatibilidade"][0], "FALHA")

    def test_other_groups_compatibility_is_outside_scope(self):
        status, _ = evaluate(captured() + [grant("IAM_ALLOWED_PRINCIPALS", database_resource("outro_grupo"), ["ALL"])])
        self.assertEqual(status, 0)

    def run_poll(self, state, timeout="3", aws_exit=0):
        with tempfile.TemporaryDirectory() as tmp:
            executable = Path(tmp) / "aws"
            executable.write_text(f'#!/bin/sh\nprintf "%s\\n" "{state}"\nexit {aws_exit}\n')
            executable.chmod(0o700)
            env = {**os.environ, "PATH": tmp + os.pathsep + os.environ["PATH"], "GLUE_POLL_SECONDS": "1", "GLUE_WAIT_TIMEOUT_SECONDS": timeout}
            return subprocess.run(["bash", "-c", 'source "$1"; wait_for_glue_run job run', "test", str(SCRIPTS / "common.sh")], env=env, capture_output=True, text=True, timeout=8)

    def test_glue_terminal_states_fail_promptly(self):
        for state in ("EXPIRED", "FAILED", "STOPPED", "TIMEOUT", "ERROR"):
            with self.subTest(state=state):
                self.assertNotEqual(self.run_poll(state).returncode, 0)

    def test_glue_success_and_api_error(self):
        self.assertEqual(self.run_poll("SUCCEEDED").returncode, 0)
        self.assertNotEqual(self.run_poll("SUCCEEDED", aws_exit=1).returncode, 0)

    def test_glue_wait_is_bounded(self):
        result = self.run_poll("RUNNING", timeout="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Timeout local", result.stderr)

    def test_glue_invalid_timeout_fails(self):
        self.assertEqual(self.run_poll("RUNNING", timeout="0").returncode, 2)

    def test_access_matrix_fails_when_sanitizer_fails(self):
        source = (SCRIPTS / "verify_access_matrix.sh").read_text()
        tail = source[source.index('mkdir -p "$EVIDENCE_DIR"\nset +e'):]
        with tempfile.TemporaryDirectory() as tmp:
            checks = Path(tmp) / "checks.tsv"
            checks.write_text("".join(f"check{i}\tallowed\tallowed\ttrue\n" for i in range(17)))
            prefix = 'set -euo pipefail\nEVIDENCE_DIR="$1"\nchecks_file="$1/checks.tsv"\nstamp=test\noutput="$1/output.json"\nsanitize_to() { cat >/dev/null; return 9; }\n'
            result = subprocess.run(["bash", "-c", prefix + tail, "test", tmp], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("PASSA:", result.stdout)


class ReportIdentityTests(unittest.TestCase):
    def test_mismatched_run_or_mode_is_rejected(self):
        import json
        source = (SCRIPTS / "run_pipeline.sh").read_text()
        validator = source.split("<<'PYREPORT'\n")[1].split("\nPYREPORT")[0]
        with tempfile.TemporaryDirectory() as tmp:
            report = Path(tmp) / "report.json"
            for run_id, mode, expected in [("jr_current", "FULL", 0), ("jr_old", "FULL", 1), ("jr_current", "BACKFILL", 1)]:
                report.write_text(json.dumps({"job_run_id": run_id, "mode": mode}))
                result = subprocess.run(["python3", "-c", validator, str(report), "jr_current", "FULL"], capture_output=True, text=True)
                self.assertEqual(result.returncode, expected)


class CatalogHardeningTests(unittest.TestCase):
    def run_hardening(self, mode, database="eda262_g09_av2"):
        import json
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            entries = [grant("IAM_ALLOWED_PRINCIPALS", database_resource(), ["ALL"]), grant("IAM_ALLOWED_PRINCIPALS", database_resource("outro_grupo"), ["ALL"]), grant("arn:aws:iam::<ACCOUNT_ID>:user/admin", database_resource(), ["ALL"])]
            (root / "grants.json").write_text(json.dumps({"PrincipalResourcePermissions": entries}))
            (root / "terraform").write_text(f'#!/bin/sh\ncase "$*" in *database*) echo "{database}";; *account_id*) echo "<ACCOUNT_ID>";; esac\n')
            (root / "aws").write_text('#!/bin/sh\nif [ "$2" = "list-permissions" ]; then cat "$TEST_ROOT/grants.json"; else cat "${4#file://}" >> "$TEST_ROOT/revoked.jsonl"; fi\n')
            for name in ("terraform", "aws"):
                (root / name).chmod(0o700)
            env = {**os.environ, "PATH": tmp + os.pathsep + os.environ["PATH"], "TEST_ROOT": tmp}
            result = subprocess.run(["bash", str(SCRIPTS / "harden_catalog.sh"), mode], env=env, capture_output=True, text=True)
            log = root / "revoked.jsonl"
            revoked = json.loads(log.read_text()) if log.exists() else None
            return result, revoked

    def test_plan_never_revokes(self):
        result, revoked = self.run_hardening("--plan")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIsNone(revoked)

    def test_apply_only_revokes_compatibility_on_project(self):
        result, revoked = self.run_hardening("--apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(revoked["Principal"]["DataLakePrincipalIdentifier"], "IAM_ALLOWED_PRINCIPALS")
        self.assertEqual(revoked["Resource"]["Database"]["Name"], "eda262_g09_av2")

    def test_other_database_is_refused(self):
        result, revoked = self.run_hardening("--apply", "other")
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(revoked)


if __name__ == "__main__":
    unittest.main()
