resource "terraform_data" "workspace_guard" {
  input = local.workspace

  lifecycle {
    precondition {
      condition     = terraform.workspace != "default"
      error_message = "Use um workspace explícito para a AV1; o workspace default não é permitido."
    }
  }
}

module "data_lake" {
  source = "./modules/data_lake"

  resource_prefix     = local.resource_prefix
  lake_bucket_name    = local.lake_bucket_name
  results_bucket_name = local.results_bucket_name
  glue_database_name  = local.database_name
  trusted_table_name  = var.trusted_table_name
  workgroup_name      = local.workgroup_name
  grain               = var.grain
  business_question   = var.business_question
  schema_columns      = var.schema_columns
  csv_delimiter       = var.csv_delimiter
  csv_has_header      = var.csv_has_header
  source_objects = {
    for name, object in var.source_objects : name => merge(object, {
      source = "${path.root}/${object.source}"
    })
  }
  athena_bytes_scanned_cutoff = var.athena_bytes_scanned_cutoff
  tags                        = local.common_tags

  depends_on = [terraform_data.workspace_guard]
}
