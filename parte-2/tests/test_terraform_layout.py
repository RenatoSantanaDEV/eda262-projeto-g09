from __future__ import annotations

import re
import unittest
from pathlib import Path

PART2 = Path(__file__).parents[1]
MODULE = PART2 / "modules" / "data_lake"
PLAN = PART2.parent / "evidencias" / "av2" / "brutas" / "terraform-plan-20261119T025835Z.txt"
OUTPUTS = {
    "account_id", "aws_region", "workspace", "raw_bucket", "trusted_bucket",
    "refined_bucket", "artifacts_bucket", "athena_results_bucket", "database",
    "raw_table", "trusted_table", "refined_table", "glue_job",
    "athena_workgroup", "layer_roles", "resource_inventory",
}


def read_all(directory: Path) -> str:
    return "\n".join(path.read_text(encoding="utf-8") for path in sorted(directory.glob("*.tf")))


def blocks(text: str, kind: str) -> list[str]:
    return re.findall(rf'^{kind} "([a-z0-9_]+)" "([a-z0-9_]+)"', text, flags=re.M)


def plan_addresses(pattern: str) -> list[str]:
    return re.findall(pattern, PLAN.read_text(encoding="utf-8"), flags=re.M)


def strip_index(address: str) -> str:
    return re.sub(r"\[.*\]$", "", address)


class TerraformLayoutTests(unittest.TestCase):
    def setUp(self) -> None:
        self.root = read_all(PART2)
        self.module = read_all(MODULE)
        self.moved = re.findall(
            r"^moved \{\n  from = (\S+)\n  to   = (\S+)\n\}$",
            (PART2 / "moved.tf").read_text(encoding="utf-8"),
            flags=re.M,
        )

    def test_root_only_calls_module(self) -> None:
        self.assertEqual(blocks(self.root, "resource"), [])
        self.assertEqual(blocks(self.root, "data"), [])
        self.assertEqual(re.findall(r'^module "([a-z_]+)"', self.root, flags=re.M), ["data_lake"])
        self.assertIn('source = "./modules/data_lake"', self.root)

    def test_every_module_resource_has_moved_block(self) -> None:
        resources = {f"{kind}.{name}" for kind, name in blocks(self.module, "resource")}
        self.assertEqual(len(resources), 36)
        self.assertEqual(len(self.moved), len(resources))
        self.assertEqual({source for source, _ in self.moved}, resources)
        for source, target in self.moved:
            self.assertEqual(target, f"module.data_lake.{source}")

    def test_recreation_plan_instances_are_covered(self) -> None:
        created = plan_addresses(r"^  # ([a-z0-9_]+\.[a-z0-9_]+(?:\[\"[a-z]+\"\])?) will be created$")
        self.assertEqual(len(created), 59)
        self.assertEqual(len(set(created)), 59)
        sources = {source for source, _ in self.moved}
        self.assertEqual({strip_index(address) for address in created}, sources)
        for_each = {strip_index(address) for address in created if "[" in address}
        self.assertTrue(for_each)
        self.assertTrue(for_each <= sources)

    def test_data_sources_match_recreation_plan(self) -> None:
        read = plan_addresses(r"^(data\.[a-z0-9_]+\.[a-z0-9_]+(?:\[\"[a-z]+\"\])?): Read complete")
        deferred = plan_addresses(r"^  # (data\.[a-z0-9_]+\.[a-z0-9_]+(?:\[\"[a-z]+\"\])?) will be read during apply$")
        instances = set(read) | set(deferred)
        self.assertEqual(len(instances), 11)
        declared = {f"data.{kind}.{name}" for kind, name in blocks(self.module, "data")}
        self.assertEqual({strip_index(address) for address in instances}, declared)

    def test_global_lake_formation_stays_removed_in_root(self) -> None:
        removed = (PART2 / "removed.tf").read_text(encoding="utf-8")
        self.assertIn("from = aws_lakeformation_data_lake_settings.av2", removed)
        self.assertRegex(removed, r"destroy\s*=\s*false")
        self.assertNotIn("removed {", self.module)
        self.assertNotIn("aws_lakeformation_data_lake_settings", self.module)

    def test_outputs_are_preserved(self) -> None:
        root_outputs = set(re.findall(r'^output "([a-z_]+)"', self.root, flags=re.M))
        module_outputs = set(re.findall(r'^output "([a-z_]+)"', self.module, flags=re.M))
        self.assertEqual(root_outputs, OUTPUTS)
        self.assertEqual(module_outputs, OUTPUTS)
        for name in OUTPUTS:
            self.assertIn(f"module.data_lake.{name}\n", self.root)

    def test_module_inputs_match_call(self) -> None:
        variables = set(re.findall(r'^variable "([a-z_]+)"', self.module, flags=re.M))
        call = re.search(r'^module "data_lake" \{\n(.*?)\n\}$', self.root, flags=re.M | re.S).group(1)
        arguments = set(re.findall(r"^  ([a-z_]+)\s+=", call, flags=re.M)) - {"source"}
        self.assertEqual(arguments, variables)
        root_variables = set(re.findall(r'^variable "([a-z_]+)"', self.root, flags=re.M))
        self.assertEqual(root_variables, variables - {"glue_script_path"})

    def test_glue_script_path_and_hash_binding(self) -> None:
        self.assertIn('glue_script_path       = "${path.module}/glue/pipeline_orders.py"', self.root)
        self.assertIn('+ source                 = "./glue/pipeline_orders.py"', PLAN.read_text(encoding="utf-8"))
        pipeline = (MODULE / "pipeline.tf").read_text(encoding="utf-8")
        self.assertEqual(pipeline.count("var.glue_script_path"), 4)
        self.assertNotIn("path.module", self.module)
        self.assertEqual(pipeline.count("filesha256(var.glue_script_path)"), 2)
        self.assertIn("etag   = filemd5(var.glue_script_path)", pipeline)

    def test_backend_example_matches_real_backend(self) -> None:
        example = (PART2 / "backend.hcl.example").read_text(encoding="utf-8")
        settings = dict(re.findall(r'^([a-z_]+)\s+=\s+"?([^"\n]+)"?$', example, flags=re.M))
        bootstrap = (PART2.parent / "parte-1" / "bootstrap" / "terraform.tfvars.example").read_text(encoding="utf-8")
        state_bucket = re.search(r'^state_bucket_name\s*=\s*"([^"]+)"', bootstrap, flags=re.M).group(1)
        group = re.search(r'^group_id\s*=\s*"([^"]+)"', bootstrap, flags=re.M).group(1)
        locals_tf = (PART2.parent / "parte-1" / "bootstrap" / "locals.tf").read_text(encoding="utf-8")
        self.assertIn('"${local.resource_prefix}-terraform-locks"', locals_tf)
        self.assertEqual(settings["bucket"], state_bucket)
        self.assertEqual(settings["bucket"], "eda262-g09-tfstate")
        self.assertEqual(settings["dynamodb_table"], f"eda262-{group}-terraform-locks")
        self.assertEqual(settings["region"], "us-east-1")
        self.assertEqual(settings["workspace_key_prefix"], "workspaces")
        self.assertEqual(settings["key"], "parte-2/terraform.tfstate")
        evidence = "\n".join(
            path.read_text(encoding="utf-8", errors="replace")
            for path in (PART2.parent / "evidencias").rglob("*") if path.is_file()
        )
        self.assertIn(settings["bucket"], evidence)
        self.assertIn(settings["dynamodb_table"], evidence)
        dedicated = (PART2 / "conta-dedicada" / "backend.hcl.example").read_text(encoding="utf-8")
        self.assertEqual(dedicated, example)

    def test_braces_are_balanced(self) -> None:
        for path in sorted(PART2.rglob("*.tf")):
            if ".terraform" in path.parts:
                continue
            text = re.sub(r'"(?:[^"\\]|\\.)*"', '""', path.read_text(encoding="utf-8"))
            with self.subTest(path=path.name):
                self.assertEqual(text.count("{"), text.count("}"))
                self.assertEqual(text.count("["), text.count("]"))


if __name__ == "__main__":
    unittest.main()
