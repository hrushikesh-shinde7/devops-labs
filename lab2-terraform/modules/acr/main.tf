resource "azurerm_container_registry" "this" {
  # ACR names must be alphanumeric only, 5-50 chars, globally unique
  name                = replace(var.name, "-", "")
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku

  # RBAC instead of admin credentials — there is no registry password anywhere
  admin_enabled = false

  tags = var.tags
}
