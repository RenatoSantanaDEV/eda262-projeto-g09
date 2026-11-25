resource "aws_glue_catalog_database" "av2" {
  name        = local.database_name
  description = "Catálogo AV2 do grupo g09: pedidos de e-commerce"

  create_table_default_permission {
    permissions = []

    principal {
      data_lake_principal_identifier = "IAM_ALLOWED_PRINCIPALS"
    }
  }
}

resource "aws_glue_catalog_table" "raw_orders" {
  name          = "raw_orders"
  database_name = aws_glue_catalog_database.av2.name
  table_type    = "EXTERNAL_TABLE"

  parameters = merge(local.raw_projection, {
    classification = "json"
  })

  partition_keys {
    name = "arrival_date"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.lake["raw"].id}/orders/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "raw-orders-json"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    dynamic "columns" {
      for_each = local.raw_columns

      content {
        name = columns.value[0]
        type = columns.value[1]
      }
    }
  }

  depends_on = [
    aws_lakeformation_permissions.executor_database,
    aws_lakeformation_permissions.executor_locations,
  ]
}

resource "aws_glue_catalog_table" "trusted_orders" {
  name          = "trusted_orders"
  database_name = aws_glue_catalog_database.av2.name
  table_type    = "EXTERNAL_TABLE"

  parameters = merge(local.event_projection, {
    classification              = "parquet"
    "storage.location.template" = "s3://${aws_s3_bucket.lake["trusted"].id}/orders/order_date=$${order_date}/"
  })

  partition_keys {
    name = "order_date"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.lake["trusted"].id}/orders/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      name                  = "trusted-orders-parquet"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    dynamic "columns" {
      for_each = local.trusted_columns

      content {
        name = columns.value[0]
        type = columns.value[1]
      }
    }
  }

  depends_on = [
    aws_lakeformation_permissions.executor_database,
    aws_lakeformation_permissions.executor_locations,
  ]
}

resource "aws_glue_catalog_table" "refined_sales" {
  name          = "refined_daily_sales"
  database_name = aws_glue_catalog_database.av2.name
  table_type    = "EXTERNAL_TABLE"

  parameters = merge(local.event_projection, {
    classification              = "parquet"
    "storage.location.template" = "s3://${aws_s3_bucket.lake["refined"].id}/daily_sales/order_date=$${order_date}/"
  })

  partition_keys {
    name = "order_date"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.lake["refined"].id}/daily_sales/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      name                  = "refined-sales-parquet"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    dynamic "columns" {
      for_each = local.refined_columns

      content {
        name = columns.value[0]
        type = columns.value[1]
      }
    }
  }

  depends_on = [
    aws_lakeformation_permissions.executor_database,
    aws_lakeformation_permissions.executor_locations,
  ]
}

