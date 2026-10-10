output "resource_group" { value = azurerm_resource_group.main.name }
output "acr_login_server" { value = module.acr.login_server }
output "aks_cluster_name" { value = module.aks.name }
output "key_vault_uri" { value = module.keyvault.vault_uri }

output "kubectl_credentials_command" {
  description = "Run this to point kubectl at the new cluster"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${module.aks.name}"
}
