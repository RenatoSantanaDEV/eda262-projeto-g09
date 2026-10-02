output "lake_bucket_name" {
  value = aws_s3_bucket.lake.id
}

output "results_bucket_name" {
  value = aws_s3_bucket.athena_results.id
}

output "glue_database_name" {
  value = aws_glue_catalog_database.this.name
}

output "glue_table_name" {
  value = aws_glue_catalog_table.trusted.name
}

output "athena_workgroup_name" {
  value = aws_athena_workgroup.this.name
}

output "athena_output_location" {
  value = "s3://${aws_s3_bucket.athena_results.id}/results/"
}
