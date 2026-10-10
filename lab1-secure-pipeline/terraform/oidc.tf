# The trust relationship that replaces a stored secret.
#
# Read the `subject` field below carefully — it is the whole security model.
# Entra ID will only accept a token whose `sub` claim matches EXACTLY. Get it
# wrong in the permissive direction and any repo in your org can assume this
# identity.
#
# Apply cost: £0. Entra app registrations and federated credentials are free.
# The role assignment costs nothing; only what you deploy costs money.

terraform {
  required_version = ">= 1.9"
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "github_org" { type = string }
variable "github_repo" { type = string }

variable "resource_group_name" {
  type        = string
  description = "The ONLY resource group this pipeline may touch."
}

data "azurerm_subscription" "current" {}

data "azurerm_resource_group" "target" {
  name = var.resource_group_name
}

resource "azuread_application" "ci" {
  display_name = "gh-oidc-${var.github_repo}"
}

resource "azuread_service_principal" "ci" {
  client_id = azuread_application.ci.client_id
}

# --- The federated credentials ------------------------------------------------
# One per trusted context. Each is narrow on purpose.

resource "azuread_application_federated_identity_credential" "main_branch" {
  application_id = azuread_application.ci.id
  display_name   = "gh-main"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"

  # Only the main branch of exactly this repo.
  subject = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"
}

resource "azuread_application_federated_identity_credential" "production_env" {
  application_id = azuread_application.ci.id
  display_name   = "gh-env-production"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"

  # Scoping to an ENVIRONMENT is stronger than scoping to a branch, because a
  # GitHub environment can require reviewers. The approval gate becomes part of
  # the authentication path, not just a UI nicety.
  subject = "repo:${var.github_org}/${var.github_repo}:environment:production"
}

# ⚠️ NEVER do this:
#
#   subject = "repo:${var.github_org}/${var.github_repo}:*"
#   subject = "repo:${var.github_org}/*:ref:refs/heads/main"
#
# The first trusts every pull_request from every fork. The second trusts every
# repo in the org. Both have caused real breaches. The wildcard is the
# vulnerability — not OIDC itself.

# --- Least privilege ----------------------------------------------------------
# Scoped to ONE resource group, not the subscription. Contributor at
# subscription scope is the single most common over-grant in Azure CI.

resource "azurerm_role_assignment" "ci_contributor" {
  scope                = data.azurerm_resource_group.target.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.ci.object_id
}

output "azure_client_id" {
  value       = azuread_application.ci.client_id
  description = "Set as the AZURE_CLIENT_ID repo VARIABLE (not a secret — it is a public identifier)."
}

output "azure_tenant_id" {
  value = data.azurerm_subscription.current.tenant_id
}

output "azure_subscription_id" {
  value = data.azurerm_subscription.current.subscription_id
}
