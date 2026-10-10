variable "environment" {
  type    = string
  default = "dev"

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be dev, stage or prod."
  }
}

variable "location" {
  type    = string
  default = "centralindia"
}

variable "node_count" {
  type    = number
  default = 1 # keep it at 1 — this costs real money
}
