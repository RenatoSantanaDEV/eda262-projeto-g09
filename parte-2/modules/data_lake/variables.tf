variable "aws_region" {
  description = "Região obrigatória da disciplina."
  type        = string

  validation {
    condition     = var.aws_region == "us-east-1"
    error_message = "A AV2 deve ser implantada exclusivamente em us-east-1."
  }
}

variable "group_id" {
  description = "Identificador oficial do grupo."
  type        = string

  validation {
    condition     = var.group_id == "g09"
    error_message = "Este módulo pertence ao grupo g09."
  }
}

variable "raw_projection_start" {
  description = "Primeiro dia aceito pela projeção da partição de chegada da raw."
  type        = string

  validation {
    condition     = can(regex("^20[0-9]{2}-[0-9]{2}-[0-9]{2}$", var.raw_projection_start))
    error_message = "Use a data no formato AAAA-MM-DD."
  }
}

variable "raw_projection_end" {
  description = "Último dia aceito pela projeção da partição de chegada da raw."
  type        = string

  validation {
    condition     = can(regex("^20[0-9]{2}-[0-9]{2}-[0-9]{2}$", var.raw_projection_end))
    error_message = "Use a data no formato AAAA-MM-DD."
  }
}

variable "event_projection_start" {
  description = "Primeiro dia aceito pela projeção das partições de evento."
  type        = string

  validation {
    condition     = can(regex("^20[0-9]{2}-[0-9]{2}-[0-9]{2}$", var.event_projection_start))
    error_message = "Use a data no formato AAAA-MM-DD."
  }
}

variable "event_projection_end" {
  description = "Último dia aceito pela projeção das partições de evento."
  type        = string

  validation {
    condition     = can(regex("^20[0-9]{2}-[0-9]{2}-[0-9]{2}$", var.event_projection_end))
    error_message = "Use a data no formato AAAA-MM-DD."
  }
}

variable "glue_workers" {
  description = "Quantidade de workers G.1X do job Glue."
  type        = number

  validation {
    condition     = var.glue_workers >= 2 && var.glue_workers <= 10
    error_message = "Use entre 2 e 10 workers."
  }
}

variable "athena_bytes_cutoff" {
  description = "Teto de bytes examinados por consulta no workgroup AV2."
  type        = number

  validation {
    condition     = var.athena_bytes_cutoff >= 10485760
    error_message = "O teto precisa ser de pelo menos 10 MiB."
  }
}

variable "glue_script_path" {
  description = "Caminho do script Glue informado pela raiz, preservando o valor registrado no estado."
  type        = string

  validation {
    condition     = fileexists(var.glue_script_path)
    error_message = "O script Glue informado não existe."
  }
}
