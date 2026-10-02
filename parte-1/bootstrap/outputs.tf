output "state_bucket_name" {
  description = "Bucket a informar em backend.hcl."
  value       = aws_s3_bucket.terraform_state.id
}

output "lock_table_name" {
  description = "Tabela a informar em backend.hcl."
  value       = aws_dynamodb_table.terraform_locks.name
}

output "backend_region" {
  description = "Região a informar em backend.hcl."
  value       = var.aws_region
}
