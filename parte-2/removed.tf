removed {
  from = aws_lakeformation_data_lake_settings.av2

  lifecycle {
    destroy = false
  }
}
