resource "aws_s3_bucket" "lake" {
  bucket        = var.lake_bucket_name
  force_destroy = true
  tags          = var.tags
}

resource "aws_s3_bucket_ownership_controls" "lake" {
  bucket = aws_s3_bucket.lake.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "lake" {
  bucket = aws_s3_bucket.lake.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lake" {
  bucket = aws_s3_bucket.lake.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "lake" {
  bucket = aws_s3_bucket.lake.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_object" "source_data" {
  for_each = var.source_objects

  bucket       = aws_s3_bucket.lake.id
  key          = each.value.key
  source       = each.value.source
  etag         = filemd5(each.value.source)
  content_type = each.value.content_type

  server_side_encryption = "AES256"
  tags                   = var.tags

  depends_on = [aws_s3_bucket_server_side_encryption_configuration.lake]
}

resource "aws_s3_bucket" "athena_results" {
  bucket        = var.results_bucket_name
  force_destroy = true
  tags          = var.tags
}

resource "aws_s3_bucket_ownership_controls" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_glue_catalog_database" "this" {
  name        = var.glue_database_name
  description = "Catálogo ${var.resource_prefix}: ${var.business_question}"
  tags        = var.tags
}

resource "aws_glue_catalog_table" "trusted" {
  name          = var.trusted_table_name
  database_name = aws_glue_catalog_database.this.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    classification           = "csv"
    "skip.header.line.count" = var.csv_has_header ? "1" : "0"
    "grain"                  = var.grain
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.lake.id}/trusted/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "${var.trusted_table_name}-csv-serde"
      serialization_library = "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe"

      parameters = {
        "field.delim"          = var.csv_delimiter
        "serialization.format" = var.csv_delimiter
      }
    }

    dynamic "columns" {
      for_each = var.schema_columns

      content {
        name    = columns.value.name
        type    = columns.value.type
        comment = columns.value.comment
      }
    }
  }
}

resource "aws_athena_workgroup" "this" {
  name        = var.workgroup_name
  description = "Consultas AV1 para ${var.business_question}"
  state       = "ENABLED"
  tags        = var.tags

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = var.athena_bytes_scanned_cutoff

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.id}/results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  depends_on = [
    aws_s3_bucket_public_access_block.athena_results,
    aws_s3_bucket_server_side_encryption_configuration.athena_results
  ]
}
