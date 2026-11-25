resource "aws_s3_object" "pipeline_script" {
  bucket = aws_s3_bucket.support["artifacts"].id
  key    = "scripts/pipeline_orders.py"
  source = var.glue_script_path
  etag   = filemd5(var.glue_script_path)

  metadata = {
    sha256 = filesha256(var.glue_script_path)
  }

  server_side_encryption = "AES256"

  depends_on = [aws_s3_bucket_server_side_encryption_configuration.support]
}

resource "aws_glue_job" "orders_pipeline" {
  name              = "${local.prefix}-av2-orders-pipeline"
  role_arn          = aws_iam_role.pipeline.arn
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = var.glue_workers
  timeout           = 30
  max_retries       = 0

  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${aws_s3_bucket.support["artifacts"].id}/${aws_s3_object.pipeline_script.key}"
  }

  default_arguments = {
    "--RAW_BUCKET"                   = aws_s3_bucket.lake["raw"].id
    "--TRUSTED_BUCKET"               = aws_s3_bucket.lake["trusted"].id
    "--REFINED_BUCKET"               = aws_s3_bucket.lake["refined"].id
    "--REPORT_BUCKET"                = aws_s3_bucket.support["artifacts"].id
    "--CODE_SHA256"                  = filesha256(var.glue_script_path)
    "--MODE"                         = "FULL"
    "--DAYS"                         = "all"
    "--job-language"                 = "python"
    "--job-bookmark-option"          = "job-bookmark-disable"
    "--enable-metrics"               = "true"
    "--enable-observability-metrics" = "true"
  }

  execution_property {
    max_concurrent_runs = 1
  }

  depends_on = [
    aws_iam_role_policy.pipeline,
    aws_iam_role_policy.pipeline_runtime,
    aws_lakeformation_permissions.pipeline_locations,
  ]
}

resource "aws_athena_workgroup" "av2" {
  name          = "${local.prefix}-av2"
  description   = "Consultas AV2 do grupo g09 sobre a camada refined"
  state         = "ENABLED"
  force_destroy = true

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = var.athena_bytes_cutoff

    result_configuration {
      output_location = "s3://${aws_s3_bucket.support["results"].id}/results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  depends_on = [
    aws_s3_bucket_public_access_block.support,
    aws_s3_bucket_server_side_encryption_configuration.support,
  ]
}

