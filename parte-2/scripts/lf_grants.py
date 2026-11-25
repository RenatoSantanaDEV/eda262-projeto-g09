#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

DATA_LOCATION = "DATA_LOCATION_ACCESS"
SUPPORTED_RESOURCES = ("DataLocation", "Database", "Table", "TableWithColumns")
DESCRIPTIONS = {
    "ingestion": "somente DATA_LOCATION_ACCESS na raw",
    "pipeline": "três localizações, DESCRIBE no database e SELECT/DESCRIBE nas três tabelas",
    "analyst": "DESCRIBE no database e SELECT/DESCRIBE somente na refined",
}
SUFFIX = "; sem extras, ALL, grant options ou wildcard"


class UnsupportedGrant(Exception):
    pass


def location(bucket: str) -> tuple[str, ...]:
    return ("location", f"arn:aws:s3:::{bucket}")


def database(name: str) -> tuple[str, ...]:
    return ("database", name)


def table(database_name: str, name: str) -> tuple[str, ...]:
    return ("table", database_name, name)


def expected_grants(args: argparse.Namespace) -> dict[str, tuple[str, set[tuple]]]:
    buckets = (args.raw_bucket, args.trusted_bucket, args.refined_bucket)
    tables = (args.raw_table, args.trusted_table, args.refined_table)
    pipeline = {(location(bucket), DATA_LOCATION) for bucket in buckets}
    pipeline.add((database(args.database), "DESCRIBE"))
    for name in tables:
        pipeline.add((table(args.database, name), "SELECT"))
        pipeline.add((table(args.database, name), "DESCRIBE"))
    return {
        "ingestion": (
            args.ingestion_arn,
            {(location(args.raw_bucket), DATA_LOCATION)},
        ),
        "pipeline": (args.pipeline_arn, pipeline),
        "analyst": (
            args.analyst_arn,
            {
                (database(args.database), "DESCRIBE"),
                (table(args.database, args.refined_table), "SELECT"),
                (table(args.database, args.refined_table), "DESCRIBE"),
            },
        ),
    }


def check_catalog(body: dict, catalog_id: str, kind: str) -> None:
    found = body.get("CatalogId")
    if found is None:
        raise UnsupportedGrant(f"{kind} sem CatalogId")
    if found != catalog_id:
        raise UnsupportedGrant(f"{kind} em catálogo inesperado {found}")


def resource_key(resource: object, catalog_id: str) -> tuple[str, tuple[str, ...]]:
    if not isinstance(resource, dict) or not resource:
        raise UnsupportedGrant("recurso ausente ou inválido")
    kinds = sorted(resource)
    unsupported = [kind for kind in kinds if kind not in SUPPORTED_RESOURCES]
    if unsupported:
        raise UnsupportedGrant(f"recurso não permitido {', '.join(unsupported)}")
    if len(kinds) != 1:
        raise UnsupportedGrant(f"recurso ambíguo {', '.join(kinds)}")
    kind = kinds[0]
    body = resource[kind]
    if not isinstance(body, dict):
        raise UnsupportedGrant(f"{kind} inválido")
    check_catalog(body, catalog_id, kind)
    if kind == "DataLocation":
        arn = body.get("ResourceArn")
        if not arn:
            raise UnsupportedGrant("DataLocation sem ResourceArn")
        return kind, ("location", arn)
    if kind == "Database":
        if not body.get("Name"):
            raise UnsupportedGrant("Database sem nome")
        return kind, database(body["Name"])
    if "TableWildcard" in body:
        raise UnsupportedGrant(f"TableWildcard no database {body.get('DatabaseName')}")
    if not body.get("DatabaseName") or not body.get("Name"):
        raise UnsupportedGrant(f"{kind} sem database ou nome")
    if kind == "TableWithColumns":
        if "ColumnNames" in body or body.get("ColumnWildcard") != {}:
            raise UnsupportedGrant(f"colunas restritas ou excluídas em {body['DatabaseName']}.{body['Name']}")
    return kind, table(body["DatabaseName"], body["Name"])


def describe(key: tuple[str, ...]) -> str:
    if key[0] == "location":
        return key[1]
    if key[0] == "database":
        return f"database {key[1]}"
    return f"tabela {key[1]}.{key[2]}"


def is_text_list(value: object) -> bool:
    return isinstance(value, list) and all(isinstance(item, str) for item in value)


def valid_entry(entry: object) -> bool:
    if not isinstance(entry, dict) or not isinstance(entry.get("Principal"), dict):
        return False
    return isinstance(entry["Principal"].get("DataLakePrincipalIdentifier"), str)


def evaluate(entries: list, principal: str, expected: set[tuple], catalog_id: str) -> list[str]:
    violations: list[str] = []
    actual: set[tuple] = set()
    for entry in entries:
        if entry["Principal"]["DataLakePrincipalIdentifier"] != principal:
            continue
        try:
            kind, key = resource_key(entry.get("Resource"), catalog_id)
        except UnsupportedGrant as error:
            violations.append(str(error))
            continue
        permissions = entry.get("Permissions", [])
        grantable = entry.get("PermissionsWithGrantOption", [])
        if not is_text_list(permissions) or not is_text_list(grantable):
            violations.append(f"lista de permissões inválida em {describe(key)}")
            continue
        if grantable:
            violations.append(f"grant option {','.join(sorted(grantable))} em {describe(key)}")
        if "ALL" in permissions or "ALL" in grantable:
            violations.append(f"ALL em {describe(key)}")
        for permission in permissions:
            if kind == "TableWithColumns" and permission != "SELECT":
                violations.append(f"{permission} em TableWithColumns de {describe(key)}")
                continue
            actual.add((key, permission))
    for key, permission in sorted(actual - expected):
        if permission != "ALL":
            violations.append(f"extra {permission} em {describe(key)}")
    for key, permission in sorted(expected - actual):
        violations.append(f"ausente {permission} em {describe(key)}")
    return violations


def compatibility_grants(entries, args):
    violations = []
    for entry in entries:
        principal = entry["Principal"]["DataLakePrincipalIdentifier"]
        if principal not in {"IAM_ALLOWED_PRINCIPALS", "IAMAllowedPrincipals"}:
            continue
        for kind, body in entry.get("Resource", {}).items():
            if not isinstance(body, dict):
                continue
            in_scope = (
                kind == "Database" and body.get("Name") == args.database
                or kind in {"Table", "TableWithColumns"} and body.get("DatabaseName") == args.database
                or kind == "DataLocation" and body.get("ResourceArn") in {
                    location(bucket)[1] for bucket in (args.raw_bucket, args.trusted_bucket, args.refined_bucket)
                }
            )
            if in_scope and body.get("CatalogId") == args.catalog_id and (entry.get("Permissions") or entry.get("PermissionsWithGrantOption")):
                violations.append(f"grant de compatibilidade {principal} em {kind} do projeto")
    return violations


def run(payload: object, args: argparse.Namespace) -> tuple[int, list[str]]:
    if not isinstance(payload, dict) or not isinstance(payload.get("PrincipalResourcePermissions"), list):
        return 2, ["FALHA\tentrada\tPrincipalResourcePermissions ausente ou inválido"]
    entries = payload["PrincipalResourcePermissions"]
    if not all(valid_entry(entry) for entry in entries):
        return 2, ["FALHA\tentrada\tregistro sem Principal.DataLakePrincipalIdentifier"]
    lines = []
    status = 0
    for label, (principal, expected) in expected_grants(args).items():
        violations = evaluate(entries, principal, expected, args.catalog_id)
        if violations:
            status = 1
            lines.append(f"FALHA\t{label}\t{'; '.join(dict.fromkeys(violations))}")
        else:
            lines.append(f"PASSA\t{label}\t{DESCRIPTIONS[label]}{SUFFIX}")
    compatibility = compatibility_grants(entries, args)
    if compatibility:
        status = 1
        lines.append("FALHA\tcompatibilidade\t" + "; ".join(compatibility))
    else:
        lines.append("PASSA\tcompatibilidade\tsem grants IAMAllowedPrincipals nos recursos do projeto")
    return status, lines


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser()
    result.add_argument("--input", required=True)
    for name in (
        "catalog-id",
        "database",
        "raw-table",
        "trusted-table",
        "refined-table",
        "raw-bucket",
        "trusted-bucket",
        "refined-bucket",
        "ingestion-arn",
        "pipeline-arn",
        "analyst-arn",
    ):
        result.add_argument(f"--{name}", required=True)
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        payload = json.loads(Path(args.input).read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        print(f"FALHA\tentrada\t{error}")
        return 2
    status, lines = run(payload, args)
    for line in lines:
        print(line)
    return status


if __name__ == "__main__":
    raise SystemExit(main())
