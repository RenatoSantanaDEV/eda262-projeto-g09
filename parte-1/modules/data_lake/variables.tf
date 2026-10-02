variable "resource_prefix" {
  description = "Prefixo eda262-gNN dos recursos."
  type        = string

  validation {
    condition     = can(regex("^eda262-g[0-9]{2}$", var.resource_prefix))
    error_message = "resource_prefix deve usar o formato eda262-gNN."
  }
}

variable "lake_bucket_name" {
  type = string
}

variable "results_bucket_name" {
  type = string
}

variable "glue_database_name" {
  type = string
}

variable "trusted_table_name" {
  type = string
}

variable "workgroup_name" {
  type = string
}

variable "grain" {
  type = string
}

variable "business_question" {
  type = string
}

variable "schema_columns" {
  type = list(object({
    name    = string
    type    = string
    comment = optional(string)
  }))
}

variable "csv_delimiter" {
  type = string
}

variable "csv_has_header" {
  type = bool
}

variable "source_objects" {
  type = map(object({
    source       = string
    key          = string
    content_type = optional(string, "text/csv")
  }))
}

variable "athena_bytes_scanned_cutoff" {
  type    = number
  default = null
}

variable "tags" {
  type = map(string)
}
