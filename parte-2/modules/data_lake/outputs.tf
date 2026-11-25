output "account_id" {
  description = "Conta usada no deploy; sanitize antes de registrar em evidências."
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  value = var.aws_region
}

output "workspace" {
  value = local.workspace
}

output "raw_bucket" {
  value = aws_s3_bucket.lake["raw"].id
}

output "trusted_bucket" {
  value = aws_s3_bucket.lake["trusted"].id
}

output "refined_bucket" {
  value = aws_s3_bucket.lake["refined"].id
}

output "artifacts_bucket" {
  value = aws_s3_bucket.support["artifacts"].id
}

output "athena_results_bucket" {
  value = aws_s3_bucket.support["results"].id
}

output "database" {
  value = aws_glue_catalog_database.av2.name
}

output "raw_table" {
  value = aws_glue_catalog_table.raw_orders.name
}

output "trusted_table" {
  value = aws_glue_catalog_table.trusted_orders.name
}

output "refined_table" {
  value = aws_glue_catalog_table.refined_sales.name
}

output "glue_job" {
  value = aws_glue_job.orders_pipeline.name
}

output "athena_workgroup" {
  value = aws_athena_workgroup.av2.name
}

output "layer_roles" {
  value = {
    ingestion = aws_iam_role.ingestion.name
    pipeline  = aws_iam_role.pipeline.name
    analyst   = aws_iam_role.analyst.name
  }
}

output "resource_inventory" {
  description = "Inventário lógico usado pelo verificador e pela documentação."
  value = {
    s3_buckets                  = 5
    glue_database               = 1
    glue_tables                 = 3
    glue_jobs                   = 1
    athena_workgroups           = 1
    iam_roles                   = 3
    lakeformation_registrations = 3
  }
}

