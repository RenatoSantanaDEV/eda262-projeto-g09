locals {
  prefix        = "eda262-${var.group_id}"
  database_name = "eda262_g09_av2"
  workspace     = terraform.workspace

  bucket_names = {
    raw       = "${local.prefix}-lake-raw"
    trusted   = "${local.prefix}-lake-trusted"
    refined   = "${local.prefix}-lake-refined"
    artifacts = "${local.prefix}-artifacts-av2"
    results   = "${local.prefix}-athena-results-av2"
  }

  raw_projection = {
    "projection.enabled"                    = "true"
    "projection.arrival_date.type"          = "date"
    "projection.arrival_date.format"        = "yyyy-MM-dd"
    "projection.arrival_date.range"         = "${var.raw_projection_start},${var.raw_projection_end}"
    "projection.arrival_date.interval"      = "1"
    "projection.arrival_date.interval.unit" = "DAYS"
    "storage.location.template"             = "s3://${local.bucket_names.raw}/orders/arrival_date=$${arrival_date}/"
  }

  event_projection = {
    "projection.enabled"                  = "true"
    "projection.order_date.type"          = "date"
    "projection.order_date.format"        = "yyyy-MM-dd"
    "projection.order_date.range"         = "${var.event_projection_start},${var.event_projection_end}"
    "projection.order_date.interval"      = "1"
    "projection.order_date.interval.unit" = "DAYS"
  }

  raw_columns = [
    ["order_id", "string"],
    ["order_item_id", "string"],
    ["customer_id", "string"],
    ["order_timestamp", "string"],
    ["status", "string"],
    ["quantity", "string"],
    ["unit_price", "string"],
    ["city", "string"],
    ["state", "string"],
    ["updated_at", "string"],
  ]

  trusted_columns = [
    ["order_id", "string"],
    ["order_item_id", "string"],
    ["customer_id", "string"],
    ["order_timestamp", "timestamp"],
    ["status", "string"],
    ["quantity", "int"],
    ["unit_price", "decimal(10,2)"],
    ["city", "string"],
    ["state", "string"],
    ["updated_at", "timestamp"],
    ["arrival_date", "string"],
  ]

  refined_columns = [
    ["status", "string"],
    ["order_count", "bigint"],
    ["item_count", "bigint"],
    ["quantity_total", "bigint"],
    ["gross_sales", "decimal(18,2)"],
  ]
}

