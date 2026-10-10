resource "azurerm_kubernetes_cluster" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  dns_prefix          = var.name

  default_node_pool {
    name       = "default"
    node_count = var.node_count
    vm_size    = var.vm_size
  }

  # System-assigned managed identity — no stored credentials
  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# Let the cluster pull from ACR without a registry password
resource "azurerm_role_assignment" "acr_pull" {
  count = var.acr_id == null ? 0 : 1

  principal_id                     = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = var.acr_id
  skip_service_principal_aad_check = true
}
