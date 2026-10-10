variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "node_count" {
  type    = number
  default = 1
}
variable "vm_size" {
  type    = string
  default = "Standard_B2s" # cheapest that runs AKS reliably
}
variable "acr_id" {
  description = "ACR resource id to grant AcrPull on. Null to skip."
  type        = string
  default     = null
}
variable "tags" {
  type    = map(string)
  default = {}
}
