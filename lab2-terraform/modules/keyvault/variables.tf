variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "tenant_id" { type = string }
variable "purge_protection" {
  type    = bool
  default = false
}
variable "secret_reader_principal_ids" {
  description = "Principals granted Key Vault Secrets User"
  type        = list(string)
  default     = []
}
variable "tags" {
  type    = map(string)
  default = {}
}
