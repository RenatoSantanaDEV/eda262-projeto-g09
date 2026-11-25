resource "aws_lakeformation_resource" "layer" {
  for_each = aws_s3_bucket.lake

  arn                     = each.value.arn
  use_service_linked_role = true
}

resource "aws_lakeformation_permissions" "executor_locations" {
  for_each = aws_lakeformation_resource.layer

  principal   = data.aws_caller_identity.current.arn
  permissions = ["DATA_LOCATION_ACCESS"]

  data_location {
    arn = each.value.arn
  }
}

resource "aws_lakeformation_permissions" "executor_database" {
  principal   = data.aws_caller_identity.current.arn
  permissions = ["ALL"]

  database {
    catalog_id = data.aws_caller_identity.current.account_id
    name       = aws_glue_catalog_database.av2.name
  }

  lifecycle {
    ignore_changes = [permissions, permissions_with_grant_option]
  }
}

resource "aws_lakeformation_permissions" "ingestion_raw_location" {
  principal   = aws_iam_role.ingestion.arn
  permissions = ["DATA_LOCATION_ACCESS"]

  data_location {
    arn = aws_lakeformation_resource.layer["raw"].arn
  }
}

resource "aws_lakeformation_permissions" "pipeline_locations" {
  for_each = aws_lakeformation_resource.layer

  principal   = aws_iam_role.pipeline.arn
  permissions = ["DATA_LOCATION_ACCESS"]

  data_location {
    arn = each.value.arn
  }
}

resource "aws_lakeformation_permissions" "pipeline_database" {
  principal = aws_iam_role.pipeline.arn
  permissions = [
    "DESCRIBE",
  ]

  database {
    catalog_id = data.aws_caller_identity.current.account_id
    name       = aws_glue_catalog_database.av2.name
  }

  lifecycle {
    ignore_changes = [permissions, permissions_with_grant_option]
  }
}

resource "aws_lakeformation_permissions" "pipeline_tables" {
  for_each = {
    raw     = aws_glue_catalog_table.raw_orders.name
    trusted = aws_glue_catalog_table.trusted_orders.name
    refined = aws_glue_catalog_table.refined_sales.name
  }

  principal = aws_iam_role.pipeline.arn
  permissions = [
    "DESCRIBE",
    "SELECT",
  ]

  table {
    database_name = aws_glue_catalog_database.av2.name
    name          = each.value
  }
}

resource "aws_lakeformation_permissions" "analyst_database" {
  principal   = aws_iam_role.analyst.arn
  permissions = ["DESCRIBE"]

  database {
    catalog_id = data.aws_caller_identity.current.account_id
    name       = aws_glue_catalog_database.av2.name
  }

  lifecycle {
    ignore_changes = [permissions, permissions_with_grant_option]
  }
}

resource "aws_lakeformation_permissions" "analyst_refined_table" {
  principal = aws_iam_role.analyst.arn
  permissions = [
    "DESCRIBE",
    "SELECT",
  ]

  table {
    database_name = aws_glue_catalog_database.av2.name
    name          = aws_glue_catalog_table.refined_sales.name
  }
}
