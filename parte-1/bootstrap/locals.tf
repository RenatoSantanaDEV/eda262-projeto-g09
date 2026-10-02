locals {
  resource_prefix = "eda262-${var.group_id}"
  lock_table_name = coalesce(
    var.lock_table_name_override,
    "${local.resource_prefix}-terraform-locks"
  )

  common_tags = {
    turma      = "eda262"
    grupo      = var.group_id
    projeto    = "engenharia-de-dados"
    managedby  = "terraform"
    finalidade = "backend-remoto"
  }
}
