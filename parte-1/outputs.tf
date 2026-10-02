output "workspace" {
  description = "Workspace usado no deploy."
  value       = local.workspace
}

output "aws_region" {
  description = "Região AWS usada no deploy."
  value       = var.aws_region
}

output "lake_bucket_name" {
  description = "Bucket S3 do Data Lake."
  value       = module.data_lake.lake_bucket_name
}

output "athena_results_bucket_name" {
  description = "Bucket S3 dos resultados do Athena."
  value       = module.data_lake.results_bucket_name
}

output "glue_database_name" {
  description = "Banco no AWS Glue Data Catalog."
  value       = module.data_lake.glue_database_name
}

output "glue_table_name" {
  description = "Tabela trusted no AWS Glue Data Catalog."
  value       = module.data_lake.glue_table_name
}

output "athena_workgroup_name" {
  description = "Workgroup usado para executar e medir consultas."
  value       = module.data_lake.athena_workgroup_name
}

output "athena_output_location" {
  description = "Local dos resultados das consultas."
  value       = module.data_lake.athena_output_location
}

output "declared_grain" {
  description = "Grão declarado para a tabela trusted."
  value       = var.grain
}

output "business_question" {
  description = "Pergunta de negócio registrada na configuração."
  value       = var.business_question
}
