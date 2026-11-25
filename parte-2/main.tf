module "data_lake" {
  source = "./modules/data_lake"

  aws_region             = var.aws_region
  group_id               = var.group_id
  raw_projection_start   = var.raw_projection_start
  raw_projection_end     = var.raw_projection_end
  event_projection_start = var.event_projection_start
  event_projection_end   = var.event_projection_end
  glue_workers           = var.glue_workers
  athena_bytes_cutoff    = var.athena_bytes_cutoff
  glue_script_path       = "${path.module}/glue/pipeline_orders.py"
}
