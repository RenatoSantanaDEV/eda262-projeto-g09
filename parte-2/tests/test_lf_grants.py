from __future__ import annotations

import copy
import importlib.util
import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

PART2 = Path(__file__).parents[1]
MODULE_PATH = PART2 / "scripts" / "lf_grants.py"
WRAPPER = PART2 / "scripts" / "verify_lf_grants.sh"
CAPTURE = PART2.parent / "evidencias" / "av2" / "brutas" / "lakeformation-g09-review.json"
SPEC = importlib.util.spec_from_file_location("lf_grants", MODULE_PATH)
assert SPEC and SPEC.loader
lf_grants = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = lf_grants
SPEC.loader.exec_module(lf_grants)

ACCOUNT = "<ACCOUNT_ID>"
DATABASE = "eda262_g09_av2"
ROLE = f"arn:aws:iam::{ACCOUNT}:role/eda262-g09-av2-"
INGESTION = ROLE + "ingestion"
PIPELINE = ROLE + "glue-pipeline"
ANALYST = ROLE + "analyst"
ARGS = [
    "--catalog-id", ACCOUNT,
    "--database", DATABASE,
    "--raw-table", "raw_orders",
    "--trusted-table", "trusted_orders",
    "--refined-table", "refined_daily_sales",
    "--raw-bucket", "eda262-g09-lake-raw",
    "--trusted-bucket", "eda262-g09-lake-trusted",
    "--refined-bucket", "eda262-g09-lake-refined",
    "--ingestion-arn", INGESTION,
    "--pipeline-arn", PIPELINE,
    "--analyst-arn", ANALYST,
]


def captured() -> list[dict]:
    payload = json.loads(CAPTURE.read_text(encoding="utf-8"))
    return copy.deepcopy(payload["PrincipalResourcePermissions"])


def grant(principal: str, resource: dict, permissions: list[str], grantable: list[str] | None = None) -> dict:
    return {
        "Principal": {"DataLakePrincipalIdentifier": principal},
        "Resource": resource,
        "Permissions": permissions,
        "PermissionsWithGrantOption": grantable or [],
    }


def database_resource(name: str = DATABASE) -> dict:
    return {"Database": {"CatalogId": ACCOUNT, "Name": name}}


def table_resource(name: str, database_name: str = DATABASE) -> dict:
    return {"Table": {"CatalogId": ACCOUNT, "DatabaseName": database_name, "Name": name}}


def columns_resource(name: str, wildcard: dict | None = None) -> dict:
    return {
        "TableWithColumns": {
            "CatalogId": ACCOUNT,
            "DatabaseName": DATABASE,
            "Name": name,
            "ColumnWildcard": {} if wildcard is None else wildcard,
        }
    }


def location_resource(layer: str) -> dict:
    return {"DataLocation": {"CatalogId": ACCOUNT, "ResourceArn": f"arn:aws:s3:::eda262-g09-lake-{layer}"}}


def evaluate(entries: list[dict]) -> tuple[int, dict[str, tuple[str, str]]]:
    args = lf_grants.parser().parse_args(["--input", "-", *ARGS])
    status, lines = lf_grants.run({"PrincipalResourcePermissions": entries}, args)
    result = {}
    for line in lines:
        outcome, label, message = line.split("\t", 2)
        result[label] = (outcome, message)
    return status, result


def without(entries: list[dict], principal: str, resource: dict) -> list[dict]:
    return [
        entry for entry in entries
        if not (entry["Principal"]["DataLakePrincipalIdentifier"] == principal and entry["Resource"] == resource)
    ]


class LakeFormationGrantTests(unittest.TestCase):
    def assert_outcomes(self, entries: list[dict], **expected: str) -> dict[str, tuple[str, str]]:
        status, result = evaluate(entries)
        for label, outcome in expected.items():
            self.assertEqual(result[label][0], outcome, result[label][1])
        self.assertEqual(status, 0 if all(value == "PASSA" for value in expected.values()) else 1)
        return result

    def test_sanitized_capture_with_api_split_passes(self) -> None:
        self.assert_outcomes(captured(), ingestion="PASSA", pipeline="PASSA", analyst="PASSA")

    def test_combined_table_representation_passes(self) -> None:
        entries = [entry for entry in captured() if "TableWithColumns" not in entry["Resource"]]
        for entry in entries:
            if "Table" in entry["Resource"]:
                entry["Permissions"] = ["DESCRIBE", "SELECT"]
        self.assert_outcomes(entries, ingestion="PASSA", pipeline="PASSA", analyst="PASSA")

    def test_other_principals_are_ignored(self) -> None:
        entries = captured() + [
            grant(f"arn:aws:iam::{ACCOUNT}:user/executor", database_resource(), ["ALL"], ["ALL"]),
            grant(f"arn:aws:iam::{ACCOUNT}:role/eda262-g01-av2-analyst", table_resource("raw_orders"), ["SELECT"]),
        ]
        self.assert_outcomes(entries, ingestion="PASSA", pipeline="PASSA", analyst="PASSA")

    def test_review_reproduction_all_grant_option_and_table_wildcard(self) -> None:
        entries = captured()
        for entry in entries:
            if "Database" in entry["Resource"]:
                entry["Permissions"] = ["ALL", "DESCRIBE"]
                entry["PermissionsWithGrantOption"] = ["ALL"]
        entries.append(grant(ANALYST, {"Table": {"CatalogId": ACCOUNT, "DatabaseName": DATABASE, "TableWildcard": {}}}, ["SELECT"]))
        result = self.assert_outcomes(entries, ingestion="PASSA", pipeline="FALHA", analyst="FALHA")
        self.assertIn("ALL em database", result["pipeline"][1])
        self.assertIn("grant option ALL", result["analyst"][1])
        self.assertIn("TableWildcard", result["analyst"][1])

    def test_review_reproduction_create_table_with_grant_option(self) -> None:
        entries = captured()
        for entry in entries:
            if entry["Principal"]["DataLakePrincipalIdentifier"] == ANALYST and "Database" in entry["Resource"]:
                entry["Permissions"] = ["DESCRIBE", "CREATE_TABLE"]
                entry["PermissionsWithGrantOption"] = ["CREATE_TABLE"]
        result = self.assert_outcomes(entries, ingestion="PASSA", pipeline="PASSA", analyst="FALHA")
        self.assertIn("extra CREATE_TABLE", result["analyst"][1])
        self.assertIn("grant option CREATE_TABLE", result["analyst"][1])

    def test_ingestion_extra_location_fails(self) -> None:
        entries = captured() + [grant(INGESTION, location_resource("trusted"), ["DATA_LOCATION_ACCESS"])]
        result = self.assert_outcomes(entries, ingestion="FALHA", pipeline="PASSA", analyst="PASSA")
        self.assertIn("eda262-g09-lake-trusted", result["ingestion"][1])

    def test_ingestion_catalog_grant_fails(self) -> None:
        entries = captured() + [grant(INGESTION, database_resource(), ["DESCRIBE"])]
        self.assert_outcomes(entries, ingestion="FALHA", pipeline="PASSA", analyst="PASSA")

    def test_analyst_select_on_raw_columns_fails(self) -> None:
        entries = captured() + [grant(ANALYST, columns_resource("raw_orders"), ["SELECT"])]
        result = self.assert_outcomes(entries, ingestion="PASSA", pipeline="PASSA", analyst="FALHA")
        self.assertIn("extra SELECT em tabela eda262_g09_av2.raw_orders", result["analyst"][1])

    def test_analyst_describe_on_trusted_fails(self) -> None:
        entries = captured() + [grant(ANALYST, table_resource("trusted_orders"), ["DESCRIBE"])]
        self.assert_outcomes(entries, ingestion="PASSA", pipeline="PASSA", analyst="FALHA")

    def test_pipeline_grant_on_other_database_fails(self) -> None:
        entries = captured() + [grant(PIPELINE, database_resource("outro_banco"), ["DESCRIBE"])]
        result = self.assert_outcomes(entries, ingestion="PASSA", pipeline="FALHA", analyst="PASSA")
        self.assertIn("database outro_banco", result["pipeline"][1])

    def test_pipeline_extra_table_permission_fails(self) -> None:
        entries = captured() + [grant(PIPELINE, table_resource("refined_daily_sales"), ["ALTER", "DROP"])]
        self.assert_outcomes(entries, ingestion="PASSA", pipeline="FALHA", analyst="PASSA")

    def test_missing_grant_fails(self) -> None:
        entries = without(captured(), PIPELINE, location_resource("trusted"))
        result = self.assert_outcomes(entries, ingestion="PASSA", pipeline="FALHA", analyst="PASSA")
        self.assertIn("ausente DATA_LOCATION_ACCESS", result["pipeline"][1])

    def test_missing_select_split_entry_fails(self) -> None:
        entries = without(captured(), ANALYST, columns_resource("refined_daily_sales"))
        result = self.assert_outcomes(entries, ingestion="PASSA", pipeline="PASSA", analyst="FALHA")
        self.assertIn("ausente SELECT", result["analyst"][1])

    def test_unsupported_resources_fail(self) -> None:
        for resource in (
            {"Catalog": {}},
            {"LFTag": {"CatalogId": ACCOUNT, "TagKey": "camada", "TagValues": ["refined"]}},
            {"DataCellsFilter": {"TableCatalogId": ACCOUNT, "DatabaseName": DATABASE, "TableName": "raw_orders", "Name": "f"}},
        ):
            with self.subTest(resource=next(iter(resource))):
                entries = captured() + [grant(ANALYST, resource, ["DESCRIBE"])]
                self.assert_outcomes(entries, ingestion="PASSA", pipeline="PASSA", analyst="FALHA")

    def test_restricted_or_excluded_columns_fail(self) -> None:
        for body in (
            {"ColumnWildcard": {"ExcludedColumnNames": ["gross_sales"]}},
            {"ColumnNames": ["status"]},
        ):
            with self.subTest(body=body):
                resource = {"TableWithColumns": {"CatalogId": ACCOUNT, "DatabaseName": DATABASE, "Name": "refined_daily_sales", **body}}
                entries = captured() + [grant(ANALYST, resource, ["SELECT"])]
                self.assert_outcomes(entries, ingestion="PASSA", pipeline="PASSA", analyst="FALHA")

    def test_foreign_catalog_fails(self) -> None:
        entries = captured()
        for entry in entries:
            if entry["Principal"]["DataLakePrincipalIdentifier"] == INGESTION:
                entry["Resource"]["DataLocation"]["CatalogId"] = "999999999999"
        self.assert_outcomes(entries, ingestion="FALHA", pipeline="PASSA", analyst="PASSA")

    def test_swapped_select_and_describe_resource_types_fail(self) -> None:
        entries = captured()
        for entry in entries:
            if "Table" in entry["Resource"]:
                entry["Permissions"] = ["SELECT"]
            elif "TableWithColumns" in entry["Resource"]:
                entry["Permissions"] = ["DESCRIBE"]
        result = self.assert_outcomes(entries, ingestion="PASSA", pipeline="FALHA", analyst="FALHA")
        self.assertIn("DESCRIBE em TableWithColumns", result["analyst"][1])
        self.assertIn("ausente DESCRIBE em tabela eda262_g09_av2.refined_daily_sales", result["analyst"][1])
        self.assertIn("DESCRIBE em TableWithColumns", result["pipeline"][1])

    def test_select_on_table_resource_is_accepted(self) -> None:
        entries = [entry for entry in captured() if "TableWithColumns" not in entry["Resource"]]
        entries += [
            grant(entry["Principal"]["DataLakePrincipalIdentifier"], copy.deepcopy(entry["Resource"]), ["SELECT"])
            for entry in entries if "Table" in entry["Resource"]
        ]
        self.assert_outcomes(entries, ingestion="PASSA", pipeline="PASSA", analyst="PASSA")

    def test_missing_catalog_id_fails(self) -> None:
        cases = (
            (INGESTION, "DataLocation", "ingestion"),
            (PIPELINE, "Database", "pipeline"),
            (ANALYST, "Table", "analyst"),
            (ANALYST, "TableWithColumns", "analyst"),
        )
        for principal, kind, label in cases:
            with self.subTest(kind=kind):
                entries = captured()
                target = next(
                    entry for entry in entries
                    if entry["Principal"]["DataLakePrincipalIdentifier"] == principal and kind in entry["Resource"]
                )
                del target["Resource"][kind]["CatalogId"]
                status, result = evaluate(entries)
                self.assertEqual(status, 1)
                self.assertEqual(result[label][0], "FALHA")
                self.assertIn(f"{kind} sem CatalogId", result[label][1])

    def test_isolated_grant_option_on_allowed_describe_fails(self) -> None:
        entries = captured()
        target = next(
            entry for entry in entries
            if entry["Principal"]["DataLakePrincipalIdentifier"] == ANALYST and "Database" in entry["Resource"]
        )
        target["PermissionsWithGrantOption"] = ["DESCRIBE"]
        result = self.assert_outcomes(entries, ingestion="PASSA", pipeline="PASSA", analyst="FALHA")
        self.assertEqual(result["analyst"][1], "grant option DESCRIBE em database eda262_g09_av2")

    def test_isolated_pipeline_table_wildcard_fails(self) -> None:
        entries = captured() + [
            grant(PIPELINE, {"Table": {"CatalogId": ACCOUNT, "DatabaseName": DATABASE, "TableWildcard": {}}}, ["DESCRIBE"])
        ]
        result = self.assert_outcomes(entries, ingestion="PASSA", pipeline="FALHA", analyst="PASSA")
        self.assertEqual(result["pipeline"][1], "TableWildcard no database eda262_g09_av2")

    def test_non_empty_column_wildcard_fails(self) -> None:
        entries = without(captured(), ANALYST, columns_resource("refined_daily_sales"))
        entries.append(grant(ANALYST, columns_resource("refined_daily_sales", {"ExcludedColumnNames": []}), ["SELECT"]))
        self.assert_outcomes(entries, ingestion="PASSA", pipeline="PASSA", analyst="FALHA")

    def test_malformed_permission_list_fails(self) -> None:
        entries = captured()
        for entry in entries:
            if entry["Principal"]["DataLakePrincipalIdentifier"] == INGESTION:
                entry["Permissions"] = "DATA_LOCATION_ACCESS"
        self.assert_outcomes(entries, ingestion="FALHA", pipeline="PASSA", analyst="PASSA")

    def test_entry_without_principal_returns_two(self) -> None:
        args = lf_grants.parser().parse_args(["--input", "-", *ARGS])
        status, lines = lf_grants.run({"PrincipalResourcePermissions": captured() + [{"Resource": {}}]}, args)
        self.assertEqual(status, 2)
        self.assertTrue(lines[0].startswith("FALHA\tentrada"))

    def test_invalid_payload_returns_two(self) -> None:
        args = lf_grants.parser().parse_args(["--input", "-", *ARGS])
        status, lines = lf_grants.run({"Outro": []}, args)
        self.assertEqual(status, 2)
        self.assertTrue(lines[0].startswith("FALHA\tentrada"))


class PaginatedWrapperTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.pages = self.root / "pages"
        self.bin.mkdir()
        self.pages.mkdir()
        aws = self.bin / "aws"
        aws.write_text(
            "#!/usr/bin/env bash\n"
            "set -u\n"
            "printf '%s\\n' \"$*\" >>\"$STUB_PAGES/calls.log\"\n"
            "[[ -f \"$STUB_PAGES/error\" ]] && { echo AccessDeniedException >&2; exit 254; }\n"
            "token=first\n"
            "while (($#)); do [[ \"$1\" == --next-token ]] && token=\"$2\"; shift; done\n"
            "cat \"$STUB_PAGES/page-$token.json\"\n",
            encoding="utf-8",
        )
        aws.chmod(aws.stat().st_mode | stat.S_IXUSR)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def write_page(self, name: str, entries: list[dict], next_token: str | None) -> None:
        payload: dict = {"PrincipalResourcePermissions": entries}
        if next_token:
            payload["NextToken"] = next_token
        (self.pages / f"page-{name}.json").write_text(json.dumps(payload), encoding="utf-8")

    def run_wrapper(self) -> subprocess.CompletedProcess:
        env = dict(os.environ)
        env["PATH"] = f"{self.bin}{os.pathsep}{env['PATH']}"
        env["STUB_PAGES"] = str(self.pages)
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        return subprocess.run(["bash", str(WRAPPER), *ARGS], capture_output=True, text=True, env=env, check=False)

    def test_split_pages_are_merged_and_pass(self) -> None:
        entries = captured()
        self.write_page("first", entries[:5], "t2")
        self.write_page("t2", entries[5:9], "t3")
        self.write_page("t3", entries[9:], None)
        result = self.run_wrapper()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.count("PASSA\t"), 4)
        self.assertEqual(len((self.pages / "calls.log").read_text().splitlines()), 3)

    def test_violation_on_last_page_is_detected(self) -> None:
        entries = captured()
        self.write_page("first", entries, "t2")
        self.write_page("t2", [grant(ANALYST, table_resource("raw_orders"), ["SELECT"])], None)
        result = self.run_wrapper()
        self.assertEqual(result.returncode, 1)
        self.assertIn("FALHA\tanalyst", result.stdout)

    def test_repeated_token_fails(self) -> None:
        self.write_page("first", captured(), "loop")
        self.write_page("loop", [], "loop")
        result = self.run_wrapper()
        self.assertEqual(result.returncode, 2)
        self.assertIn("token de paginação repetido", result.stdout)

    def test_api_error_fails(self) -> None:
        (self.pages / "error").write_text("", encoding="utf-8")
        result = self.run_wrapper()
        self.assertEqual(result.returncode, 2)
        self.assertIn("AccessDeniedException", result.stdout)

    def test_invalid_page_fails(self) -> None:
        (self.pages / "page-first.json").write_text("{\"Outro\": 1}", encoding="utf-8")
        result = self.run_wrapper()
        self.assertEqual(result.returncode, 2)
        self.assertIn("resposta inválida", result.stdout)


if __name__ == "__main__":
    unittest.main()
