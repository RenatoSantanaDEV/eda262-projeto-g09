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
    error_message = "group_id deve usar exatamente o formato gNN, por exemplo g07."
  }
}

variable "scenario" {
  description = "Cenário em minúsculas, com palavras separadas por hífen."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(?:-[a-z0-9]+)*$", var.scenario))
    error_message = "scenario deve conter apenas minúsculas, números e hífens internos."
  }
}

variable "business_question" {
  description = "Pergunta de negócio respondida pela consulta Athena."
  type        = string

  validation {
    condition     = length(trimspace(var.business_question)) >= 10
    error_message = "business_question deve registrar a pergunta de negócio real."
  }
}

variable "grain" {
  description = "Declaração explícita do que cada linha da tabela trusted representa."
  type        = string

  validation {
    condition     = length(trimspace(var.grain)) >= 10
    error_message = "grain deve descrever explicitamente o grão da tabela trusted."
  }
}

variable "lake_layer" {
  description = "Camada do Data Lake usada na AV1."
  type        = string
  default     = "trusted"

  validation {
    condition     = var.lake_layer == "trusted"
    error_message = "A Parte 1 deste scaffold usa obrigatoriamente a camada trusted."
  }
}

variable "database_name_override" {
  description = "Nome opcional do banco Glue. Nulo usa nome derivado compatível com Athena."
  type        = string
  default     = null
}

variable "trusted_table_name" {
  description = "Nome da tabela trusted no Glue Data Catalog."
  type        = string
  default     = "trusted"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]*$", var.trusted_table_name))
    error_message = "trusted_table_name deve ser compatível com identificadores do Athena."
  }
}

variable "schema_columns" {
  description = "Schema declarado da tabela, sem inferência por Crawler."
  type = list(object({
    name    = string
    type    = string
    comment = optional(string)
  }))

  validation {
    condition = length(var.schema_columns) > 0 && alltrue([
      for column in var.schema_columns :
      can(regex("^[a-z][a-z0-9_]*$", column.name)) && length(trimspace(column.type)) > 0
    ])
    error_message = "schema_columns deve ter ao menos uma coluna com nome e tipo válidos."
  }
}

variable "csv_delimiter" {
  description = "Delimitador confirmado do CSV."
  type        = string
  default     = ","

  validation {
    condition     = length(var.csv_delimiter) == 1
    error_message = "csv_delimiter deve conter exatamente um caractere."
  }
}

variable "csv_has_header" {
  description = "Informa se a primeira linha do CSV contém cabeçalho."
  type        = bool
  default     = true
}

variable "source_objects" {
  description = "Arquivos locais enviados pelo Terraform para a camada trusted."
  type = map(object({
    source       = string
    key          = string
    content_type = optional(string, "text/csv")
  }))
  default = {}

  validation {
    condition = alltrue([
      for object in values(var.source_objects) : startswith(object.key, "trusted/")
    ])
    error_message = "Toda chave de source_objects deve começar com trusted/."
  }
}

variable "athena_bytes_scanned_cutoff" {
  description = "Limite opcional de bytes examinados por consulta no workgroup."
  type        = number
  default     = null

  validation {
    condition     = var.athena_bytes_scanned_cutoff == null ? true : var.athena_bytes_scanned_cutoff >= 10000000
    error_message = "O cutoff do Athena deve ser nulo ou ao menos 10 MB."
  }
}

variable "extra_tags" {
  description = "Tags adicionais sem sobrescrever as tags obrigatórias."
  type        = map(string)
  default     = {}
}
