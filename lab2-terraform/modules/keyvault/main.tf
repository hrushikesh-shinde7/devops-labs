resource "azurerm_key_vault" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = var.tenant_id
  sku_name            = "standard"

  # RBAC rather than the legacy access-policy model
  rbac_authorization_enabled = true

  # purge protection is essential in prod and infuriating in dev:
  # a purge-protected vault name is unusable for 7-90 days after deletion
  purge_protection_enabled   = var.purge_protection
  soft_delete_retention_days = 7

  tags = var.tags

  # EXERCISE: uncomment, then try `terraform destroy` and watch it refuse.
  # lifecycle {
  #   prevent_destroy = true
  # }
}

# Grant a principal (e.g. the AKS kubelet identity) read access to secrets
resource "azurerm_role_assignment" "secrets_user" {
  for_each = toset(var.secret_reader_principal_ids)

  principal_id         = each.value
  role_definition_name = "Key Vault Secrets User"
  scope                = azurerm_key_vault.this.id
}
