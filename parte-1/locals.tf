locals {
  resource_prefix = "eda262-${var.group_id}"
  workspace       = terraform.workspace

  common_tags = merge(var.extra_tags, {
    turma     = "eda262"
    grupo     = var.group_id
    projeto   = "engenharia-de-dados"
    cenario   = var.scenario
    workspace = local.workspace
    managedby = "terraform"
  })

  lake_bucket_name    = "${local.resource_prefix}-lake-${var.lake_layer}"
  results_bucket_name = "${local.resource_prefix}-athena-results"
  workgroup_name      = "${local.resource_prefix}-athena"

  derived_database_name = replace(
    "${local.resource_prefix}-${var.scenario}-catalog",
    "-",
    "_"
  )
  database_name = coalesce(var.database_name_override, local.derived_database_name)
}
