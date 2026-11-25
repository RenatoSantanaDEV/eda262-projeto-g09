variable "aws_region" {
  type    = string
  default = "us-east-1"

  validation {
    condition     = var.aws_region == "us-east-1"
    error_message = "A região obrigatória é us-east-1."
  }
}

variable "state_bucket_name" {
  type    = string
  default = "eda262-g09-av2-tfstate"

  validation {
    condition     = can(regex("^eda262-g09-[a-z0-9-]+$", var.state_bucket_name))
    error_message = "O bucket deve começar com eda262-g09-."
  }
}

variable "lock_table_name" {
  type    = string
  default = "eda262-g09-av2-terraform-locks"

  validation {
    condition     = startswith(var.lock_table_name, "eda262-g09-")
    error_message = "A tabela deve começar com eda262-g09-."
  }
}

