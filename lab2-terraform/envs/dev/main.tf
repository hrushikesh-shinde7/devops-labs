# ---------------------------------------------------------------------------
# DEV ENVIRONMENT — 💰 creates real, billable Azure resources.
# Run `terraform destroy` the same day.
# ---------------------------------------------------------------------------

data "azurerm_client_config" "current" {}

locals {
  name_prefix = "hotelops-${var.environment}"

  common_tags = {
    environment = var.environment
    managed_by  = "terraform"
    lab         = "devops-prep-lab2"
  }
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.common_tags
}

module "acr" {
  source = "../../modules/acr"

  name                = "acr${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.common_tags
}

module "aks" {
  source = "../../modules/aks"

  name                = "aks-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  node_count          = var.node_count
  acr_id              = module.acr.id # wires up AcrPull — no registry password
  tags                = local.common_tags
}

module "keyvault" {
  source = "../../modules/keyvault"

  name                = "kv-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tenant_id           = data.azurerm_client_config.current.tenant_id

  # conditional: protection in prod, convenience in dev
  purge_protection = var.environment == "prod"

  # let the cluster read secrets — workload identity, no stored credential
  secret_reader_principal_ids = [module.aks.kubelet_identity_object_id]

  tags = local.common_tags
}
