variable "aws_region" {
  description = "Região obrigatória da disciplina: N. Virginia."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = var.aws_region == "us-east-1"
    error_message = "A disciplina exige exclusivamente a região us-east-1 (N. Virginia)."
  }
}

variable "group_id" {
  description = "Identificador do grupo no formato gNN."
  type        = string

  validation {
    condition     = can(regex("^g[0-9]{2}$", var.group_id))
    error_message = "group_id deve usar exatamente o formato gNN."
  }
}

variable "state_bucket_name" {
  description = "Nome globalmente único do bucket de estado, iniciado por eda262-gNN-."
  type        = string

  validation {
    condition     = can(regex("^eda262-g[0-9]{2}-[a-z0-9-]+$", var.state_bucket_name))
    error_message = "state_bucket_name deve iniciar com eda262-gNN- e ser válido para S3."
  }
}

variable "lock_table_name_override" {
  description = "Nome opcional da tabela DynamoDB de lock."
  type        = string
  default     = null
}
