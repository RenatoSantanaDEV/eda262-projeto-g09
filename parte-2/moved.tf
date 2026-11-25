moved {
  from = aws_athena_workgroup.av2
  to   = module.data_lake.aws_athena_workgroup.av2
}

moved {
  from = aws_glue_catalog_database.av2
  to   = module.data_lake.aws_glue_catalog_database.av2
}

moved {
  from = aws_glue_catalog_table.raw_orders
  to   = module.data_lake.aws_glue_catalog_table.raw_orders
}

moved {
  from = aws_glue_catalog_table.refined_sales
  to   = module.data_lake.aws_glue_catalog_table.refined_sales
}

moved {
  from = aws_glue_catalog_table.trusted_orders
  to   = module.data_lake.aws_glue_catalog_table.trusted_orders
}

moved {
  from = aws_glue_job.orders_pipeline
  to   = module.data_lake.aws_glue_job.orders_pipeline
}

moved {
  from = aws_iam_role.analyst
  to   = module.data_lake.aws_iam_role.analyst
}

moved {
  from = aws_iam_role.ingestion
  to   = module.data_lake.aws_iam_role.ingestion
}

moved {
  from = aws_iam_role.pipeline
  to   = module.data_lake.aws_iam_role.pipeline
}

moved {
  from = aws_iam_role_policy.analyst
  to   = module.data_lake.aws_iam_role_policy.analyst
}

moved {
  from = aws_iam_role_policy.ingestion
  to   = module.data_lake.aws_iam_role_policy.ingestion
}

moved {
  from = aws_iam_role_policy.pipeline
  to   = module.data_lake.aws_iam_role_policy.pipeline
}

moved {
  from = aws_iam_role_policy.pipeline_runtime
  to   = module.data_lake.aws_iam_role_policy.pipeline_runtime
}

moved {
  from = aws_lakeformation_permissions.analyst_database
  to   = module.data_lake.aws_lakeformation_permissions.analyst_database
}

moved {
  from = aws_lakeformation_permissions.analyst_refined_table
  to   = module.data_lake.aws_lakeformation_permissions.analyst_refined_table
}

moved {
  from = aws_lakeformation_permissions.executor_database
  to   = module.data_lake.aws_lakeformation_permissions.executor_database
}

moved {
  from = aws_lakeformation_permissions.executor_locations
  to   = module.data_lake.aws_lakeformation_permissions.executor_locations
}

moved {
  from = aws_lakeformation_permissions.ingestion_raw_location
  to   = module.data_lake.aws_lakeformation_permissions.ingestion_raw_location
}

moved {
  from = aws_lakeformation_permissions.pipeline_database
  to   = module.data_lake.aws_lakeformation_permissions.pipeline_database
}

moved {
  from = aws_lakeformation_permissions.pipeline_locations
  to   = module.data_lake.aws_lakeformation_permissions.pipeline_locations
}

moved {
  from = aws_lakeformation_permissions.pipeline_tables
  to   = module.data_lake.aws_lakeformation_permissions.pipeline_tables
}

moved {
  from = aws_lakeformation_resource.layer
  to   = module.data_lake.aws_lakeformation_resource.layer
}

moved {
  from = aws_s3_bucket.lake
  to   = module.data_lake.aws_s3_bucket.lake
}

moved {
  from = aws_s3_bucket.support
  to   = module.data_lake.aws_s3_bucket.support
}

moved {
  from = aws_s3_bucket_ownership_controls.lake
  to   = module.data_lake.aws_s3_bucket_ownership_controls.lake
}

moved {
  from = aws_s3_bucket_ownership_controls.support
  to   = module.data_lake.aws_s3_bucket_ownership_controls.support
}

moved {
  from = aws_s3_bucket_policy.lake_tls
  to   = module.data_lake.aws_s3_bucket_policy.lake_tls
}

moved {
  from = aws_s3_bucket_policy.support_tls
  to   = module.data_lake.aws_s3_bucket_policy.support_tls
}

moved {
  from = aws_s3_bucket_public_access_block.lake
  to   = module.data_lake.aws_s3_bucket_public_access_block.lake
}

moved {
  from = aws_s3_bucket_public_access_block.support
  to   = module.data_lake.aws_s3_bucket_public_access_block.support
}

moved {
  from = aws_s3_bucket_server_side_encryption_configuration.lake
  to   = module.data_lake.aws_s3_bucket_server_side_encryption_configuration.lake
}

moved {
  from = aws_s3_bucket_server_side_encryption_configuration.support
  to   = module.data_lake.aws_s3_bucket_server_side_encryption_configuration.support
}

moved {
  from = aws_s3_bucket_versioning.artifacts
  to   = module.data_lake.aws_s3_bucket_versioning.artifacts
}

moved {
  from = aws_s3_bucket_versioning.raw
  to   = module.data_lake.aws_s3_bucket_versioning.raw
}

moved {
  from = aws_s3_object.pipeline_script
  to   = module.data_lake.aws_s3_object.pipeline_script
}

moved {
  from = terraform_data.workspace_guard
  to   = module.data_lake.terraform_data.workspace_guard
}
