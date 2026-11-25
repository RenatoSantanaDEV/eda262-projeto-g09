from __future__ import annotations

import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

FOLDER = Path(__file__).parents[1] / "conta-dedicada"
PREFLIGHT = FOLDER / "preflight.sh"
REGISTER = FOLDER / "registrar_admin_lf.sh"
SHARED = "325583868777"
TARGET = "111122223333"
USER_ARN = f"arn:aws:iam::{TARGET}:user/avaliador-g09"
READ_ONLY = {
    "sts get-caller-identity",
    "s3api head-bucket",
    "s3api get-bucket-versioning",
    "dynamodb describe-table",
    "lakeformation get-data-lake-settings",
    "lakeformation list-resources",
    "glue get-database",
    "glue get-job",
    "athena get-work-group",
    "iam get-role",
}
LOCK_TABLE = {
    "Table": {
        "TableStatus": "ACTIVE",
        "KeySchema": [{"AttributeName": "LockID", "KeyType": "HASH"}],
        "AttributeDefinitions": [{"AttributeName": "LockID", "AttributeType": "S"}],
    }
}
STUB = r"""#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >>"$STUB_DIR/calls.log"
operation="$1 $2"
name=""
owner=""
token="first"
settings_file=""
previous=""
for argument in "$@"; do
  case "$previous" in
    --bucket|--table-name|--name|--role-name|--job-name|--work-group) name="$argument" ;;
    --expected-bucket-owner) owner="$argument" ;;
    --next-token) token="$argument" ;;
    --data-lake-settings) settings_file="${argument#file://}" ;;
  esac
  previous="$argument"
done
denied() {
  echo "An error occurred (AccessDeniedException) when calling the $1 operation: User is not authorized" >&2
  exit 254
}
[[ -f "$STUB_DIR/denied-$operation" ]] && denied "$operation"
case "$operation" in
  "sts get-caller-identity")
    printf '{"Account": "%s", "Arn": "%s", "UserId": "AIDEXEMPLO"}\n' "$STUB_ACCOUNT" "$STUB_ARN" ;;
  "s3api head-bucket"|"s3api get-bucket-versioning")
    [[ "$owner" == "$STUB_ACCOUNT" ]] || { echo "sem expected-bucket-owner" >&2; exit 98; }
    state="$(cat "$STUB_DIR/bucket-$name" 2>/dev/null || echo 404)"
    case "$state" in
      own)
        if [[ "$operation" == "s3api get-bucket-versioning" ]]; then
          cat "$STUB_DIR/versioning-$name" 2>/dev/null || echo '{"Status": "Enabled"}'
        fi
        exit 0 ;;
      403) echo "An error occurred (403) when calling the HeadBucket operation: Forbidden" >&2; exit 254 ;;
      301) echo "An error occurred (301) when calling the HeadBucket operation: Moved Permanently" >&2; exit 254 ;;
      500) echo "An error occurred (500) when calling the HeadBucket operation: Internal" >&2; exit 254 ;;
      *) echo "An error occurred (404) when calling the HeadBucket operation: Not Found" >&2; exit 254 ;;
    esac ;;
  "dynamodb describe-table")
    [[ -f "$STUB_DIR/lock.json" ]] && { cat "$STUB_DIR/lock.json"; exit 0; }
    echo "An error occurred (ResourceNotFoundException) when calling the DescribeTable operation" >&2; exit 254 ;;
  "lakeformation get-data-lake-settings")
    cat "$STUB_DIR/settings.json" ;;
  "lakeformation put-data-lake-settings")
    jq '{DataLakeSettings: .}' "$settings_file" >"$STUB_DIR/settings.json" ;;
  "lakeformation list-resources")
    cat "$STUB_DIR/lf-page-$token.json" 2>/dev/null || echo '{"ResourceInfoList": []}' ;;
  "glue get-database"|"glue get-job")
    [[ -f "$STUB_DIR/glue-$name" ]] && { echo '{}'; exit 0; }
    echo "An error occurred (EntityNotFoundException) when calling the operation: Entity Not Found" >&2; exit 254 ;;
  "athena get-work-group")
    [[ -f "$STUB_DIR/workgroup-$name" ]] && { echo '{}'; exit 0; }
    echo "An error occurred (InvalidRequestException) when calling the GetWorkGroup operation: WorkGroup $name is not found." >&2; exit 254 ;;
  "iam get-role")
    [[ -f "$STUB_DIR/role-$name" ]] && { echo '{}'; exit 0; }
    echo "An error occurred (NoSuchEntity) when calling the GetRole operation" >&2; exit 254 ;;
  *)
    echo "operação inesperada: $*" >&2; exit 99 ;;
esac
"""


class DedicatedAccountTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.state = self.root / "state"
        self.bin.mkdir()
        self.state.mkdir()
        aws = self.bin / "aws"
        aws.write_text(STUB, encoding="utf-8")
        aws.chmod(aws.stat().st_mode | stat.S_IXUSR)
        (self.state / "lock.json").write_text(json.dumps(LOCK_TABLE), encoding="utf-8")
        (self.state / "bucket-eda262-g09-tfstate").write_text("own", encoding="utf-8")
        self.settings = {
            "DataLakeAdmins": [{"DataLakePrincipalIdentifier": f"arn:aws:iam::{TARGET}:user/outro-admin"}],
            "CreateDatabaseDefaultPermissions": [
                {"Principal": {"DataLakePrincipalIdentifier": "IAM_ALLOWED_PRINCIPALS"}, "Permissions": ["ALL"]}
            ],
            "CreateTableDefaultPermissions": [],
            "Parameters": {"CROSS_ACCOUNT_VERSION": "4"},
        }
        self.write_settings(self.settings)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def write_settings(self, settings: dict) -> None:
        (self.state / "settings.json").write_text(json.dumps({"DataLakeSettings": settings}), encoding="utf-8")

    def read_settings(self) -> dict:
        return json.loads((self.state / "settings.json").read_text(encoding="utf-8"))["DataLakeSettings"]

    def calls(self) -> list[str]:
        log = self.state / "calls.log"
        return log.read_text(encoding="utf-8").splitlines() if log.exists() else []

    def run_script(self, script: Path, *args: str, target: str | None = TARGET, confirm: str | None = TARGET,
                   account: str = TARGET, arn: str = USER_ARN, extra: dict | None = None) -> subprocess.CompletedProcess:
        env = {key: value for key, value in os.environ.items() if not key.startswith(("CONTA_", "CONFIRMA_", "AWS_"))}
        env.update({
            "PATH": f"{self.bin}{os.pathsep}{os.environ['PATH']}",
            "STUB_DIR": str(self.state),
            "STUB_ACCOUNT": account,
            "STUB_ARN": arn,
        })
        if target is not None:
            env["CONTA_DEDICADA_ID"] = target
        if confirm is not None:
            env["CONFIRMA_CONTA_DEDICADA"] = confirm
        env.update(extra or {})
        return subprocess.run(["bash", str(script), *args], capture_output=True, text=True, env=env, check=False)

    def admin(self) -> None:
        settings = dict(self.settings)
        settings["DataLakeAdmins"] = settings["DataLakeAdmins"] + [{"DataLakePrincipalIdentifier": USER_ARN}]
        self.write_settings(settings)

    def assert_read_only(self) -> None:
        for call in self.calls():
            self.assertIn(" ".join(call.split()[:2]), READ_ONLY, call)

    def test_missing_target_is_blocked_before_aws(self) -> None:
        result = self.run_script(PREFLIGHT, target=None, confirm=None)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.calls(), [])

    def test_shared_account_is_blocked_before_aws(self) -> None:
        for script in (PREFLIGHT, REGISTER):
            with self.subTest(script=script.name):
                result = self.run_script(script, target=SHARED, confirm=SHARED, account=SHARED)
                self.assertEqual(result.returncode, 2)
                self.assertIn("conta compartilhada", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_confirmation_must_match(self) -> None:
        result = self.run_script(PREFLIGHT, confirm="999999999999")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.calls(), [])

    def test_credentials_from_shared_account_are_blocked(self) -> None:
        result = self.run_script(PREFLIGHT, account=SHARED, arn=f"arn:aws:iam::{SHARED}:user/eda-grupo09")
        self.assertEqual(result.returncode, 2)
        self.assertIn("conta compartilhada", result.stderr)
        self.assertEqual(len(self.calls()), 1)

    def test_credentials_from_other_account_are_blocked(self) -> None:
        result = self.run_script(PREFLIGHT, account="444455556666", arn="arn:aws:iam::444455556666:user/x")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(len(self.calls()), 1)

    def test_assumed_role_is_blocked(self) -> None:
        result = self.run_script(PREFLIGHT, arn=f"arn:aws:sts::{TARGET}:assumed-role/admin/sessao")
        self.assertEqual(result.returncode, 2)
        self.assertIn("usuário IAM", result.stderr)

    def test_ready_account_passes_read_only(self) -> None:
        self.admin()
        result = self.run_script(PREFLIGHT)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("0 ALERTA, 0 FALHA", result.stdout)
        self.assertIn("Nenhuma alteração foi feita", result.stdout)
        self.assert_read_only()

    def test_missing_prerequisites_are_alerts(self) -> None:
        (self.state / "lock.json").unlink()
        (self.state / "bucket-eda262-g09-tfstate").unlink()
        result = self.run_script(PREFLIGHT)
        self.assertEqual(result.returncode, 3, result.stdout)
        self.assertIn("3 ALERTA, 0 FALHA", result.stdout)
        self.assert_read_only()

    def test_bucket_in_other_region_fails(self) -> None:
        self.admin()
        (self.state / "bucket-eda262-g09-lake-raw").write_text("301", encoding="utf-8")
        result = self.run_script(PREFLIGHT)
        self.assertEqual(result.returncode, 1)
        self.assertIn("eda262-g09-lake-raw com verificação inconclusiva", result.stdout)

    def test_global_name_collision_fails(self) -> None:
        self.admin()
        (self.state / "bucket-eda262-g09-lake-raw").write_text("403", encoding="utf-8")
        (self.state / "bucket-eda262-g09-tfstate").write_text("403", encoding="utf-8")
        result = self.run_script(PREFLIGHT)
        self.assertEqual(result.returncode, 1)
        self.assertIn("eda262-g09-lake-raw pertence a outra conta ou o acesso foi negado", result.stdout)
        self.assertIn("coordene a liberação", result.stdout)
        self.assertIn("escolha outro nome eda262-g09-*", result.stdout)
        self.assert_read_only()

    def test_existing_stack_and_inconclusive_checks_fail(self) -> None:
        self.admin()
        for name in ("glue-eda262_g09_av2", "glue-eda262-g09-av2-orders-pipeline",
                     "workgroup-eda262-g09-av2", "role-eda262-g09-av2-analyst"):
            (self.state / name).write_text("", encoding="utf-8")
        (self.state / "bucket-eda262-g09-lake-trusted").write_text("own", encoding="utf-8")
        (self.state / "bucket-eda262-g09-lake-refined").write_text("500", encoding="utf-8")
        result = self.run_script(PREFLIGHT)
        self.assertEqual(result.returncode, 1)
        self.assertIn("6 FALHA", result.stdout)
        self.assertIn("job eda262-g09-av2-orders-pipeline já existe", result.stdout)
        self.assertIn("workgroup eda262-g09-av2 já existe", result.stdout)

    def test_every_bucket_call_checks_owner(self) -> None:
        self.admin()
        result = self.run_script(PREFLIGHT)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        bucket_calls = [call for call in self.calls() if call.startswith("s3api ")]
        self.assertEqual(len(bucket_calls), 7)
        for call in bucket_calls:
            self.assertIn(f"--expected-bucket-owner {TARGET}", call)

    def test_backend_versioning_must_be_enabled(self) -> None:
        self.admin()
        for content, message in (
            ('{"Status": "Suspended"}', "sem versionamento Enabled"),
            ("{}", "sem versionamento Enabled"),
        ):
            with self.subTest(content=content):
                (self.state / "versioning-eda262-g09-tfstate").write_text(content, encoding="utf-8")
                result = self.run_script(PREFLIGHT)
                self.assertEqual(result.returncode, 1)
                self.assertIn(message, result.stdout)

    def test_backend_versioning_denied_fails_closed(self) -> None:
        self.admin()
        (self.state / "denied-s3api get-bucket-versioning").write_text("", encoding="utf-8")
        result = self.run_script(PREFLIGHT)
        self.assertEqual(result.returncode, 1)
        self.assertIn("versionamento do bucket de estado não pôde ser confirmado", result.stdout)

    def test_lock_table_must_be_active_with_lock_id(self) -> None:
        self.admin()
        cases = (
            {"Table": {**LOCK_TABLE["Table"], "TableStatus": "CREATING"}},
            {"Table": {**LOCK_TABLE["Table"], "KeySchema": [{"AttributeName": "Id", "KeyType": "HASH"}]}},
            {"Table": {**LOCK_TABLE["Table"], "AttributeDefinitions": [{"AttributeName": "LockID", "AttributeType": "N"}]}},
        )
        for table in cases:
            with self.subTest(table=table):
                (self.state / "lock.json").write_text(json.dumps(table), encoding="utf-8")
                result = self.run_script(PREFLIGHT)
                self.assertEqual(result.returncode, 1)
                self.assertIn("não está ACTIVE ou não tem chave LockID", result.stdout)

    def test_access_denied_is_not_absence(self) -> None:
        self.admin()
        for operation, message in (
            ("dynamodb describe-table", "tabela de lock: acesso negado"),
            ("glue get-job", "job eda262-g09-av2-orders-pipeline: acesso negado"),
            ("athena get-work-group", "workgroup eda262-g09-av2: acesso negado"),
            ("iam get-role", "acesso negado; ausência não confirmada"),
            ("lakeformation get-data-lake-settings", "leitura das configurações do Lake Formation negada"),
            ("lakeformation list-resources", "listagem de registros falhou na página 1 (negado)"),
        ):
            with self.subTest(operation=operation):
                denied = self.state / f"denied-{operation}"
                denied.write_text("", encoding="utf-8")
                result = self.run_script(PREFLIGHT)
                denied.unlink()
                self.assertEqual(result.returncode, 1, result.stdout)
                self.assertIn(message, result.stdout)

    def test_lake_formation_registrations_are_paginated(self) -> None:
        self.admin()
        (self.state / "lf-page-first.json").write_text(json.dumps({
            "ResourceInfoList": [{"ResourceArn": "arn:aws:s3:::eda262-g01-lake-raw"}],
            "NextToken": "p2",
        }), encoding="utf-8")
        (self.state / "lf-page-p2.json").write_text(json.dumps({
            "ResourceInfoList": [{"ResourceArn": "arn:aws:s3:::eda262-g09-lake-refined"}],
        }), encoding="utf-8")
        result = self.run_script(PREFLIGHT)
        self.assertEqual(result.returncode, 1)
        self.assertIn("arn:aws:s3:::eda262-g09-lake-refined já registrada", result.stdout)
        self.assertIn("arn:aws:s3:::eda262-g09-lake-raw não registrada", result.stdout)
        self.assertEqual(sum("list-resources" in call for call in self.calls()), 2)

    def test_lake_formation_registration_with_prefix_path_fails(self) -> None:
        self.admin()
        (self.state / "lf-page-first.json").write_text(json.dumps({
            "ResourceInfoList": [{"ResourceArn": "arn:aws:s3:::eda262-g09-lake-raw/orders"}],
        }), encoding="utf-8")
        result = self.run_script(PREFLIGHT)
        self.assertEqual(result.returncode, 1)
        self.assertIn("eda262-g09-lake-raw já registrada", result.stdout)

    def test_lake_formation_pagination_fails_closed(self) -> None:
        self.admin()
        for pages, message in (
            ({"first": {"ResourceInfoList": [], "NextToken": "loop"}, "loop": {"ResourceInfoList": [], "NextToken": "loop"}},
             "token repetido"),
            ({"first": {"Outro": 1, "ResourceInfoList": "x"}}, "resposta inválida"),
        ):
            with self.subTest(message=message):
                for path in self.state.glob("lf-page-*.json"):
                    path.unlink()
                for token, payload in pages.items():
                    (self.state / f"lf-page-{token}.json").write_text(json.dumps(payload), encoding="utf-8")
                result = self.run_script(PREFLIGHT)
                self.assertEqual(result.returncode, 1)
                self.assertIn(message, result.stdout)

    def test_backend_name_must_keep_prefix(self) -> None:
        result = self.run_script(PREFLIGHT, extra={"BACKEND_BUCKET": "outro-bucket"})
        self.assertEqual(result.returncode, 2)

    def test_register_dry_run_does_not_write(self) -> None:
        result = self.run_script(REGISTER)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("administradores 1 -> 2", result.stdout)
        self.assertIn("Nenhuma alteração foi feita", result.stdout)
        self.assert_read_only()
        self.assertEqual(self.read_settings(), self.settings)

    def test_register_apply_requires_confirmation(self) -> None:
        result = self.run_script(REGISTER, "--aplicar")
        self.assertEqual(result.returncode, 2)
        self.assert_read_only()
        self.assertEqual(self.read_settings(), self.settings)

    def test_register_apply_preserves_other_fields(self) -> None:
        result = self.run_script(
            REGISTER, "--aplicar", extra={"CONFIRMA_ALTERACAO_LF": f"adicionar-admin-{TARGET}"}
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        updated = self.read_settings()
        self.assertEqual(
            [admin["DataLakePrincipalIdentifier"] for admin in updated["DataLakeAdmins"]],
            [f"arn:aws:iam::{TARGET}:user/outro-admin", USER_ARN],
        )
        for key in ("CreateDatabaseDefaultPermissions", "CreateTableDefaultPermissions", "Parameters"):
            self.assertEqual(updated[key], self.settings[key])
        self.assertEqual(sum("put-data-lake-settings" in call for call in self.calls()), 1)

    def test_register_is_idempotent(self) -> None:
        self.admin()
        result = self.run_script(
            REGISTER, "--aplicar", extra={"CONFIRMA_ALTERACAO_LF": f"adicionar-admin-{TARGET}"}
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn("nada a alterar", result.stdout)
        self.assert_read_only()

    def test_register_rejects_unknown_mode(self) -> None:
        result = self.run_script(REGISTER, "--forcar")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.calls(), [])


if __name__ == "__main__":
    unittest.main()
