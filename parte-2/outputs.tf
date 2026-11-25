output "account_id" {
  description = "Conta usada no deploy; sanitize antes de registrar em evidências."
  value       = module.data_lake.account_id
}

output "aws_region" {
  value = module.data_lake.aws_region
}

output "workspace" {
  value = module.data_lake.workspace
}

output "raw_bucket" {
  value = module.data_lake.raw_bucket
}

output "trusted_bucket" {
  value = module.data_lake.trusted_bucket
}

output "refined_bucket" {
  value = module.data_lake.refined_bucket
}

output "artifacts_bucket" {
  value = module.data_lake.artifacts_bucket
}

output "athena_results_bucket" {
  value = module.data_lake.athena_results_bucket
}

output "database" {
  value = module.data_lake.database
}

output "raw_table" {
  value = module.data_lake.raw_table
}

output "trusted_table" {
  value = module.data_lake.trusted_table
}

output "refined_table" {
  value = module.data_lake.refined_table
}

output "glue_job" {
  value = module.data_lake.glue_job
}

output "athena_workgroup" {
  value = module.data_lake.athena_workgroup
}

output "layer_roles" {
  value = module.data_lake.layer_roles
}

output "resource_inventory" {
  description = "Inventário lógico usado pelo verificador e pela documentação."
  value       = module.data_lake.resource_inventory
}
